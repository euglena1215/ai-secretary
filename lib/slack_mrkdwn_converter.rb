# frozen_string_literal: true

class SlackMrkdwnConverter
  def self.convert(text)
    new.convert(text)
  end

  def convert(text)
    lines = text.lines(chomp: true)
    result = []
    i = 0

    while i < lines.size
      line = lines[i]

      # テーブル: ヘッダー行 + 区切り行 + データ行をまとめて変換
      if table_start?(line, lines, i)
        table_lines = extract_table(lines, i)
        result.concat(convert_table(table_lines))
        i += table_lines.size
        next
      end

      result << convert_line(line)
      i += 1
    end

    result.join("\n")
  end

  private

  def convert_line(line)
    # 見出し: ### heading → *heading*
    if line.match?(/\A\s*\#{1,6}\s/)
      heading = line.sub(/\A\s*\#{1,6}\s+/, "").strip
      return "*#{heading}*"
    end

    # 水平線: --- or *** or ___
    if line.match?(/\A\s*[-*_]{3,}\s*\z/)
      return "━━━━━━━━━━"
    end

    line = convert_inline(line)
    line
  end

  def convert_inline(text)
    # リンク: [text](url) → <url|text>
    text = text.gsub(/\[([^\]]+)\]\(([^)]+)\)/) { "<#{$2}|#{$1}>" }

    # 太字: **text** → *text*
    text = text.gsub(/\*\*(.+?)\*\*/, '*\1*')

    text
  end

  def table_start?(line, lines, index)
    return false unless line.include?("|")
    return false if index + 1 >= lines.size

    # 次の行が区切り行（|---|---|）かチェック
    separator_line?(lines[index + 1])
  end

  def separator_line?(line)
    line.match?(/\A\s*\|[\s\-:|]+\|\s*\z/)
  end

  def extract_table(lines, start)
    table = []
    i = start
    while i < lines.size && lines[i].include?("|")
      table << lines[i]
      i += 1
    end
    table
  end

  def convert_table(table_lines)
    rows = table_lines
      .reject { |l| separator_line?(l) }
      .map { |l| parse_table_row(l) }

    return [] if rows.empty?

    headers = rows.first
    data_rows = rows[1..]

    result = []

    if data_rows.nil? || data_rows.empty?
      result << headers.reject(&:empty?).map { |h| "*#{h}*" }.join(" | ")
    else
      data_rows.each do |row|
        parts = headers.zip(row).reject { |h, _| h.empty? }.map { |h, v| "*#{h}:* #{v}" }
        label = row.first if headers.first.empty?
        if label
          result << "*#{label}*  #{parts.join("  ")}"
        else
          result << parts.join("  ")
        end
      end
    end

    result.map { |line| convert_inline(line) }
  end

  def parse_table_row(line)
    # 先頭と末尾の | を除去してから分割（空セルを保持するため）
    trimmed = line.sub(/\A\s*\|/, "").sub(/\|\s*\z/, "")
    trimmed.split("|").map(&:strip)
  end
end
