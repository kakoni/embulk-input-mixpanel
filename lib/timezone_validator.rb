class TimezoneValidator
  def initialize(timezone)
    @timezone = timezone
  end

  def validate
    begin
      # raises exception if timezone is invalid string
      TZInfo::Timezone.get(@timezone)
    rescue => e
      Embulk.logger.error "'#{@timezone}' is invalid timezone"
      raise Embulk::ConfigError, e.message
    end
  end
end
