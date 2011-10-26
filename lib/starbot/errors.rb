class Starbot
  module Error; end
  class StandardError < ::StandardError; include(Error) end
  class MissingAnswerFile < StandardError; end
  class InvalidCommitNotification < StandardError; end
  class ConfigurationError < StandardError; end
  class UndefinedHelper < StandardError; end
end # class::Starbot