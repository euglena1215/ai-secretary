# frozen_string_literal: true

require "slack-ruby-client"
require "slack_socket_mode_bot"
require "logger"
require "net/http"
require "tmpdir"
require "fileutils"
require_relative "slack_mrkdwn_converter"

class SlackBot
  SUPPORTED_MIMETYPES = %w[image/jpeg image/png image/gif image/webp application/pdf].freeze
  PROCESSING_REACTIONS = %w[eyes hourglass_flowing_sand].freeze

  def initialize(bot_token:, app_token:, claude_executor:, session_store:, channel_router:, event_deduplicator:, active_reaction_store:)
    @logger = Logger.new($stdout)
    @claude_executor = claude_executor
    @session_store = session_store
    @channel_router = channel_router
    @event_deduplicator = event_deduplicator
    @active_reaction_store = active_reaction_store

    Slack.configure do |config|
      config.token = bot_token
    end
    @web_client = Slack::Web::Client.new

    @bot = SlackSocketModeBot.new(
      token: bot_token,
      app_token: app_token,
      logger: @logger
    ) do |data|
      handle_event(data)
    end
  end

  def start
    @logger.info("Connecting to Slack via Socket Mode...")
    cleanup_active_reactions
    @bot.run
  end

  private

  def handle_event(data)
    return unless data[:type] == "events_api"

    event_id = data[:payload][:event_id]
    event = data[:payload][:event]

    if event_id && @event_deduplicator.already_processed?(event_id)
      @logger.debug("Skipping duplicate event: #{event_id}")
      return
    end

    return unless event[:type] == "message"
    return if event[:bot_id]
    return if event[:subtype] && event[:subtype] != "file_share"

    channel_id = event[:channel]

    unless @channel_router.known_channel?(channel_id)
      @logger.debug("Ignoring message from unknown channel: #{channel_id}")
      return
    end

    Thread.new { process_message(event) }
  rescue => e
    @logger.error("handle_event error: #{e.class}: #{e.message}")
    @logger.error(e.backtrace.first(5).join("\n"))
  end

  def process_message(event)
    channel_id = event[:channel]
    thread_ts = event[:thread_ts] || event[:ts]
    text = event[:text] || ""

    channel_config = @channel_router.route(channel_id)
    files = event[:files] || []

    @logger.info("Processing message: channel=#{channel_id} user=#{event[:user]} text=#{text} files=#{files.size}")

    supported_files, unsupported_files = files.partition { |f| SUPPORTED_MIMETYPES.include?(f[:mimetype]) }

    # サポート外ファイルのみでテキストもない場合は早期返却
    if unsupported_files.any? && supported_files.empty? && text.strip.empty?
      @web_client.chat_postMessage(
        channel: channel_id,
        text: unsupported_files_message(unsupported_files),
        thread_ts: thread_ts
      )
      return
    end

    # サポート対象ファイルをダウンロード
    tmpdir = nil
    downloaded_paths = []
    if supported_files.any?
      tmpdir = Dir.mktmpdir("slack_files_")
      downloaded_paths = download_files(supported_files, tmpdir)
    end

    query = build_query_with_files(text, downloaded_paths)

    reaction = PROCESSING_REACTIONS.sample
    add_reaction(channel_id, event[:ts], reaction)

    session_id = @session_store.find(channel_id: channel_id, thread_ts: thread_ts)
    response = @claude_executor.call(
      query: query,
      session_id: session_id,
      system_prompt: channel_config&.system_prompt_path,
      working_directory: channel_config&.working_directory
    )
    @session_store.save(channel_id: channel_id, thread_ts: thread_ts, session_id: response[:session_id])

    result_text = response[:result]
    if unsupported_files.any?
      result_text += "\n\n#{unsupported_files_message(unsupported_files)}"
    end
    result_text += "\n\n#{format_context_usage(response[:context_usage])}" if response[:context_usage]

    @web_client.chat_postMessage(
      channel: channel_id,
      text: SlackMrkdwnConverter.convert(result_text),
      thread_ts: thread_ts
    )

    remove_reaction(channel_id, event[:ts], reaction)
  rescue => e
    @logger.error("Error handling message: #{e.message}")
    @logger.error(e.backtrace.first(5).join("\n"))

    remove_reaction(channel_id, event[:ts], reaction) if event && reaction
    notify_error(event, e) if event
  ensure
    FileUtils.rm_rf(tmpdir) if tmpdir
  end

  def download_files(files, tmpdir)
    files.filter_map do |file|
      download_slack_file(file[:url_private], file[:name], tmpdir)
    end
  end

  def download_slack_file(url, filename, tmpdir)
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{@web_client.token}"

    response = http.request(request)
    unless response.code == "200"
      @logger.error("Failed to download file: #{filename} (HTTP #{response.code})")
      return nil
    end

    path = File.join(tmpdir, filename)
    File.binwrite(path, response.body)
    @logger.info("Downloaded file: #{path} (#{response.body.bytesize} bytes)")
    path
  rescue => e
    @logger.error("Failed to download file #{filename}: #{e.message}")
    nil
  end

  def build_query_with_files(text, file_paths)
    return text if file_paths.empty?

    file_refs = file_paths.map { |path| "添付ファイル: #{path}" }.join("\n")

    if text.strip.empty?
      "添付ファイルの内容を確認してください。\n#{file_refs}"
    else
      "#{text}\n\n#{file_refs}"
    end
  end

  def unsupported_files_message(files)
    names = files.map { |f| "・#{f[:name]} (#{f[:mimetype]})" }.join("\n")
    "添付ファイルの読み取りに対応していない形式が含まれています:\n#{names}\n\n読み取り可能な形式: 画像(JPEG, PNG, GIF, WebP)、PDF"
  end

  def add_reaction(channel, timestamp, name)
    @web_client.reactions_add(channel: channel, timestamp: timestamp, name: name)
    @active_reaction_store.save(channel_id: channel, timestamp: timestamp, name: name)
  rescue => e
    @logger.error("Failed to add reaction: #{e.message}")
  end

  def remove_reaction(channel, timestamp, name)
    @web_client.reactions_remove(channel: channel, timestamp: timestamp, name: name)
    @active_reaction_store.delete(channel_id: channel, timestamp: timestamp, name: name)
  rescue => e
    @logger.error("Failed to remove reaction: #{e.message}")
  end

  def cleanup_active_reactions
    reactions = @active_reaction_store.read_all
    return if reactions.empty?

    @logger.info("Found #{reactions.size} orphaned reaction(s), cleaning up...")
    reactions.each do |r|
      @web_client.reactions_remove(
        channel: r["channel_id"],
        timestamp: r["message_ts"],
        name: r["reaction_name"]
      )
      @logger.info("Removed orphaned reaction #{r['reaction_name']} from channel=#{r['channel_id']}")
    rescue => e
      @logger.error("Failed to remove orphaned reaction: #{e.message}")
    end
    @active_reaction_store.clear!
  end

  def format_context_usage(context_usage)
    used_k = (context_usage[:used] / 1000.0).round
    limit_k = (context_usage[:limit] / 1000.0).round
    limit_display = limit_k >= 1000 ? "#{limit_k / 1000}M" : "#{limit_k}K"
    "（#{used_k}K/#{limit_display}）"
  end

  def notify_error(event, error)
    thread_ts = event[:thread_ts] || event[:ts]
    message = case error
              when ClaudeExecutionError
                "エラーが発生しました。しばらくしてからもう一度お試しください。"
              when JSON::ParserError
                "応答の解析に失敗しました。"
              else
                "予期しないエラーが発生しました（#{error.class}: #{error.message}）"
              end

    @web_client.chat_postMessage(
      channel: event[:channel],
      text: message,
      thread_ts: thread_ts
    )
  rescue => e
    @logger.error("Failed to send error message: #{e.message}")
  end
end
