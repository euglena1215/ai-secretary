# frozen_string_literal: true

class ChannelRouter
  ChannelConfig = Struct.new(:name, :system_prompt_path, :working_directory, keyword_init: true)

  def initialize
    @routes = {}

    # SLACK_CHANNEL_1, SLACK_CHANNEL_2, ... の環境変数からチャンネルを登録
    # 対応する System Prompt: config/prompts/channel_1.txt, config/prompts/channel_2.txt, ...
    # 対応するチャンネル名（任意）: SLACK_CHANNEL_1_NAME
    # 対応する作業ディレクトリ（任意）: SLACK_CHANNEL_1_WORKDIR
    (1..10).each do |i|
      channel_id = ENV["SLACK_CHANNEL_#{i}"]
      next unless channel_id && !channel_id.empty?

      name = ENV["SLACK_CHANNEL_#{i}_NAME"] || "channel_#{i}"
      prompt_path = "config/prompts/channel_#{i}.txt"
      working_directory = ENV["SLACK_CHANNEL_#{i}_WORKDIR"]

      @routes[channel_id] = ChannelConfig.new(
        name: name,
        system_prompt_path: File.exist?(prompt_path) ? prompt_path : nil,
        working_directory: working_directory
      )
    end
  end

  def route(channel_id)
    @routes[channel_id]
  end

  def known_channel?(channel_id)
    @routes.key?(channel_id)
  end

  def channel_name(channel_id)
    config = @routes[channel_id]
    config ? config.name : channel_id
  end
end
