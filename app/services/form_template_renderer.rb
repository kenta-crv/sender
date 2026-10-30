# 文面の {{キー}} を、会社の template_vars（JSON文字列）で置き換える。
# 使うキーは job_title / company / area。
# 値がないときは {{キー|代わりの文言}} の代わりの文言を使い、なければ空文字にする。
class FormTemplateRenderer
  KEYS = %w[job_title company area].freeze
  PLACEHOLDER = /\{\{\s*(#{KEYS.join("|")})\s*(?:\|([^{}]*))?\}\}/

  Result = Struct.new(:content, :title, :error, :logged, keyword_init: true)

  def self.render(content:, title:, template_vars:)
    vars = parse_vars(template_vars)
    original_content = content.to_s
    original_title = title.to_s
    rendered_content = substitute(original_content, vars)
    rendered_title = substitute(original_title, vars)

    Result.new(
      content: rendered_content,
      title: rendered_title,
      error: interpolation_error(rendered_content, rendered_title),
      logged: [original_content, original_title].any? { |text| text.include?("{{") || text.include?("}}") }
    )
  end

  def self.parse_vars(raw)
    return {} if raw.blank?

    data = JSON.parse(raw)
    return {} unless data.is_a?(Hash)

    data.each_with_object({}) { |(key, value), hash| hash[key.to_s] = value }
  rescue JSON::ParserError
    {}
  end

  def self.substitute(text, vars)
    text.gsub(PLACEHOLDER) do
      key = Regexp.last_match(1)
      fallback = Regexp.last_match(2)
      value = vars[key].to_s.strip
      if value.present?
        value
      elsif fallback.nil?
        ""
      else
        fallback.strip
      end
    end
  end

  def self.interpolation_error(content, title)
    leftovers = []
    leftovers << "本文" if unresolved?(content)
    leftovers << "件名" if unresolved?(title)
    return nil if leftovers.empty?

    "未解決の差し込みが残っています（#{leftovers.join("・")}）"
  end

  def self.unresolved?(text)
    text.include?("{{") || text.include?("}}")
  end

  private_class_method :substitute, :interpolation_error, :unresolved?
end
