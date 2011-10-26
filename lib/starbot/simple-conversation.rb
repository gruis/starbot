class Starbot
  class SimpleConversation < Conversation
    def initialize(msg, *args, &blk)
      super(msg, *args)
      instance_eval(&blk).tap{|ret| say("#{ret}") unless ret.nil? }
      if waiting_for_resp?
        on(:intercept_end) { unregister_with_router }
      else
        unregister_with_router
      end # waiting_for_resp?
    end # initialize(msg, &blk)
    
    def waiting_for_resp?
      !@intercept.nil?
    end # waiting_for_resp?
    
    def answers
      bot.answers
    end # answers
    
    def answer(*args)
      # do nothing
    end # answer(*args)
    def conversation(*args)
      # do nothing
    end # conversation(*args)
  end # class::SimpleConversation < Conversation
end # class::Starbot