# frozen_string_literal: true

require "open3"
require "json"
require "timeout"

class ClaudeExecutionError < StandardError; end

class ClaudeExecutor
  EXECUTION_TIMEOUT = 1800 # 30分

  def initialize(logger: Logger.new($stdout))
    @logger = logger
  end

  # @param query [String] ユーザーからのメッセージ
  # @param session_id [String, nil] 既存セッションを継続する場合のセッションID
  # @param system_prompt [String, nil] System Prompt ファイルパス
  # @param working_directory [String, nil] コマンドを実行するディレクトリ（nil の場合は現在のディレクトリ）
  # @return [Hash] { result: String, session_id: String }
  def call(query:, session_id: nil, system_prompt: nil, working_directory: nil)
    cmd = build_command(query, session_id, system_prompt)
    @logger.info("Executing: #{cmd.join(' ')}")

    stdout, stderr, status = execute_with_timeout(cmd, working_directory)

    unless status.success?
      @logger.error("Claude CLI failed: #{stderr}")
      raise ClaudeExecutionError, "Claude CLI failed (exit #{status.exitstatus}): #{stderr}"
    end

    parsed = JSON.parse(stdout)
    {
      result: parsed["result"],
      session_id: parsed["session_id"],
      context_usage: extract_context_usage(parsed)
    }
  end

  private

  def extract_context_usage(parsed)
    model_usage = parsed.dig("modelUsage")
    return nil unless model_usage

    usage = model_usage.values.first
    return nil unless usage

    input = usage["inputTokens"].to_i + usage["cacheReadInputTokens"].to_i + usage["cacheCreationInputTokens"].to_i
    output = usage["outputTokens"].to_i
    { used: input + output, limit: usage["contextWindow"].to_i }
  rescue
    nil
  end

  def execute_with_timeout(cmd, working_directory = nil)
    stdout = ""
    stderr = ""
    status = nil

    popen3_opts = {}
    popen3_opts[:chdir] = working_directory if working_directory

    Open3.popen3(*cmd, **popen3_opts) do |stdin, stdout_io, stderr_io, wait_thr|
      stdin.close
      pid = wait_thr.pid

      stdout_reader = Thread.new { stdout_io.read }
      stderr_reader = Thread.new { stderr_io.read }

      begin
        Timeout.timeout(EXECUTION_TIMEOUT) do
          status = wait_thr.value
        end
        stdout = stdout_reader.value
        stderr = stderr_reader.value
      rescue Timeout::Error
        @logger.error("Claude CLI timed out after #{EXECUTION_TIMEOUT}s, killing process (pid=#{pid})")
        begin
          Process.kill("TERM", pid)
          unless wait_thr.join(5)
            Process.kill("KILL", pid)
            wait_thr.join
          end
        rescue Errno::ESRCH
          # プロセスが既に終了している場合は無視
        end
        stdout_reader.kill
        stderr_reader.kill
        raise ClaudeExecutionError, "Claude CLI timed out after #{EXECUTION_TIMEOUT} seconds"
      end
    end

    [stdout, stderr, status]
  end

  def build_command(query, session_id, system_prompt)
    cmd = [
      "claude", "-p", query,
      "--output-format", "json",
      "--dangerously-skip-permissions"
    ]
    cmd += ["--append-system-prompt", File.read(system_prompt)] if system_prompt
    cmd += ["--resume", session_id] if session_id
    cmd
  end
end
