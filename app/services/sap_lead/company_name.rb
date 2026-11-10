module SapLead
  module CompanyName
    BRANCH_WORDS = %w[オフィス 支店 営業所 サテライト 事業所 支社 センター].freeze
    BRANCH_PATTERN = /(?:#{BRANCH_WORDS.join("|")})\z/.freeze
    TRUNCATED_PATTERN = /(?:\.\.\.|…|．．．)\z/.freeze

    def self.tidy(name)
      value = strip_trailing_note(name.to_s.strip)
      value = drop_truncated_word(value) if value.match?(TRUNCATED_PATTERN)
      strip_branch(value)
    end

    def self.normalize(name)
      strip_trailing_note(name.to_s.unicode_normalize(:nfkc)).gsub(/[[:space:]]+/, "")
    end

    def self.strip_trailing_note(name)
      name.to_s.split(%r{[／/(（]}, 2).first.to_s.strip
    end

    def self.drop_truncated_word(name)
      value = name.sub(TRUNCATED_PATTERN, "").strip
      parts = value.split(/[[:space:]]+/)
      parts.pop if parts.size > 1
      parts.join(" ")
    end

    def self.strip_branch(name)
      value = name.to_s.strip
      return value unless value.match?(BRANCH_PATTERN)

      parts = value.split(/[[:space:]]+/)
      if parts.size > 1 && parts.last.match?(BRANCH_PATTERN)
        return parts[0..-2].join(" ")
      end

      value.sub(BRANCH_PATTERN, "").strip
    end
    private_class_method :drop_truncated_word, :strip_branch, :strip_trailing_note
  end
end
