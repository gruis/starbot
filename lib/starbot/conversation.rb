# encoding: utf-8
class Starbot
  class Conversation
    class << self
      attr_writer :bot, :wrappers, :name, :desc
      # Answers to questions that can be asked at any time during a Conversation
      def answers
        @answers ||= {}
      end # answers
      
      def bot
        @bot || raise("I don't know how to reach my bot")
      end # bot
      # Holds code to execute at the start and end or the conversation
      def wrappers
        @wrappers ||= {:before => {:all => [], :each => []}, :after => {:all => [], :each => []}}
      end # wrappers
      
      # Code to execute either at the start of the conversation or as each response is received
      # @param [Symbol] scope :all, or :each
      def before(scope, &blk)
        raise ArgumentError, "scope must be either :all, or :each" unless [:all, :each].include?(scope)
        wrappers[:before][scope].push(blk)
      end # before(scope, &blk)
      
      # Code to execute either at the end of the conversation or after each response is sent
      # @param [Symbol] scope :all, or :each
      def after(scope, &blk)
        raise ArgumentError, "scope must be either :all, or :each" unless [:all, :each].include?(scope)
        wrappers[:after][scope].push(blk)
      end # after(scope, &blk)
    end # << self
    
    attr_reader :events, :raw, :params, :opts, :bot
    attr_accessor :desc, :name
    
    def initialize(msg, *args)
      @raw            = msg
      @msg            = msg
      @opts           = args.last.is_a?(Hash) ? args.pop : {}
      @params         = args
      
      @answers        = []
      @level          = 0
      @bot            = self.class.bot
      @room           = msg.room
      @contact        = msg.contact
      @first_question = msg.txt
      # See #on
      @events         = {}
      # Listeners for specific rooms and contacts that are not in this conversation
      @listeners      = {}
      # An intercept for this specific conversation. It overrides any handlers defined
      # at any level of the conversation
      @intercept      = nil
      
      on(:no_answer) { end_conversation }
      on(:branch_end) { end_conversation }
      always_answer("go back") { go_back(2) }
      always_answer("help") do
        say(%Q{you started this conversation by asking, "#{@first_question}"} )
        say("At level #{@level - 1} I'll respond to:")
        say("·  " + answers(@level - 1).keys.join("\n·  "))
      end
      always_answer("end conversation") { end_conversation }
      
      self.class.wrappers[:before][:all].each { |wrapper| instance_eval(&wrapper) }
      register_with_router
    end # initialize(msg)
    
    # Any methods that are defined in Starbot are accessible in the Conversations through
    # this method_missing. If they are not available in the Starbot then the method call 
    # will go to the superclass.
    def method_missing(meth, *args, &blk)
      if self.class.bot.respond_to?(meth)
        block_given? ? self.class.bot.send(meth, *args, &blk) : self.class.bot.send(meth, *args)
      else
        block_given? ? super(meth, *args, &blk) : super(meth, *args)
      end # self.class.bot.respond_to?(meth)
    end # method_missing(meth, *args, &blk)
    
    # Causes starbot to remember a fact. 
    # A remembered fact can be recalled from any conversation and will
    # survive a restart of the bot.
    # @param [String, Symbol] key
    # @param [Object] value
    def remember(key, value)
      self.class.bot.remember(key, value)
    end # remember(key, value)
    def recal(key, dflt = nil)
      self.class.bot.recal(key, dflt)
    end # recal(key)
    def forget(key)
      self.class.bot.forget(key)
    end # forget(key)
    
    # Asks a question and yields the response (the next message)
    # @param [String] question
    def ask(question)
      say("#{question}") if question.is_a?(String)
      intercept_until do |resp|
        yield(resp)
        true
      end #  |txt, resp|
      nil
    end # ask(msg, question)
    
    # Asks for agreement to the given question. If the response is n[o], or y[es]
    # then false or true is yielded. If the response is not n[o], or y[es] then
    # asks the user to respond yes or no.
    # @param [String] question
    def agree?(question)
      (question[-1] == '?' ? question : "#{question}?").tap do |q|
        say(q)
      end #  |q|

      intercept_until do |msg|
        resp = msg.downcase
        if resp == 'y' || resp == 'yes'
          yield(true, msg)
          true
        elsif resp == 'n' || resp == 'no'
          yield(false, msg)
          true
        else
          say("please answer yes, or no")
          false
        end # resp == 'y' || resp == 'yes'
      end #  |txt, msg|
      nil
    end # agree?(msg, question)
    
    # Routes all messages from the given room (@room) and optional contact (@contact)
    # to the given block until the block returns true, or until the conversation ends.
    # @param [Room] rm (@room)
    # @param [Contact, nil] ctct (@contact)
    def listen_until(rm = @room, ctct = @contact, &blk)
      return unless block_given?
      @listeners["#{rm}:#{ctct}"] = blk
      if events[:conversation_end].nil?
        on(:conversation_end) { @listeners.each {|k,b| bot.stop_watching(*k.split(":"), &b) }}
      end # events[:conversation_end].nil?
      bot.watch_until(rm, ctct, &blk)
    end # listen_until(room = @room, contact = @contact)
    
    # Stop listening to the given room and contact. Use this method to cancel #listen_until
    # without ending the conversation.
    def stop_listening(rm = @room, ctct = @contact)
      return if @listeners["#{rm}:#{ctct}"].nil?
      bot.stop_watching(rm, ctct, &@listeners["#{rm}:#{ctct}"])
    end # stop_listening(rm = @room, ctct = @contact)
    
    
    # Returns the list of available answers at the current level
    def answers(lev = @level)
      @answers[lev] ||= {}
    end # answers
    
    # Creates an answer to a question that can be asked at any level of
    # the conversation. Any previously defined 'always answer' for the 
    # given question will be overriden. Answers defiend by #answer at
    # any level that share the same 'question' will override the 
    # 'always answer'
    # @param [String]
    def always_answer(question, &blk)
      self.class.answers[question] = blk
    end # always_answer(question, &blk)
    
    # Goes back up a level in the conversation
    def go_back(amt = 1)
      @level -= amt
      @level = 0 if @level < 0
      @answers = @answers[0..@level]
      @level
    end # go_back
    
    # Assigns a handler to a particular event. Currently supported events are:
    #  :branch_end - there are no more answers defined below the current answer
    #  :no_answer - the user asked a question that does not match any questions
    #               defined for this conversation.
    #  :conversation_end - the converstaion has ended
    def on(event, &blk)
      case event
      when :branch_end
        @events[:branch_end] = blk
      when :no_answer
        @events[:no_answer] = blk
      when :intercept_end 
        @events[:intercept_end] = blk
      when :conversation_end
        @events[:conversation_end] = blk
      end # event
    end # on(event, &blk)
    
    # Signals the router that the conversation is over
    def end_conversation
      unless @ended
        self.class.wrappers[:after][:all].each { |wrapper| instance_eval(&wrapper) } 
        instance_eval &@events[:conversation_end] unless @events[:conversation_end].nil?
        say("conversation, '#{@first_question}' is over.")
      end
      @ended = true
      true
    end # end_conversation

    # Signals that the convesation is not oever
    def continue_conversation
      false
    end # continue_conversation
    
    
    def register_with_router
      bot.watch_until(@room, @contact, &watch_proc)
      nil
    end # register_with_router
    def unregister_with_router
      bot.stop_watching(@room, @contact, &watch_proc)
      nil
    end # unregister_with_router
    
    def answer(question, &blk)
      return answers[question] unless block_given?
      answers[question] = blk
    end # answer(question, &blk)
    
    def say(msg)
      bot.sayto(@room || @contact, msg)
    end
    def sayto(addr, msg)
      bot.sayto(addr, msg)
    end
    def sayloud(msg)
      bot.sayloudto(@room || @contact, msg)
    end
    def sayloudto(addr, msg)
      bot.sayloudto(addr, msg)
    end
    
    
    # Access a previously defined helper
    # @param [Symbol] name
    def helper(name, *args)
      bot.helper(name, *args)
    end # helper(name, *args)
    
    def helpers
      bot.helpers
    end # helpers
    
    def log
      bot.log
    end # log
    
    # The number of seconds that the bot has been up for.
    def uptime
      bot.uptime
    end # uptime

    # Retrieve all contacts
    def contacts
      bot.contacts
    end # contacts

    # Find a contact by alias or id
    # @param [String] qry
    # @return [Contact, nil]
    # @todo look for contacts in the same room with an alias equivalent to qry
    #       then look for any contact with the alias
    def contact(qry = nil)
      return @contact if qry.nil?
      room.nil? ? bot.contact(qry) : bot.contact(qry, :room => room.id)
    end # contact(qry)

    # Retrieve all rooms
    def rooms
      bot.rooms
    end # rooms

    # Find's a room by alias or id
    # @param [String]
    # @return [Room, nil]
    def room(qry = nil)
      return @room if qry.nil?
      bot.room(qry)
    end # room(qry)
    
    def scheduled
      bot.scheduled
    end # scheduled
    
    
    def bot
      self.class.bot
    end # bot
    def wrappers
      self.class.wrappers
    end # wrappers
    
    
    # Causes the given block to intercept all incoming messages in this conversation until the
    # block returns true.
    def intercept_until(&blk)
      @intercept = blk
    end # watch_until(room, contact = nil)
    
  private
    
    def watch_proc
      @watch_proc ||= (Proc.new do |txt, msg|
        begin
          if !@intercept.nil?
            if @intercept.call(msg) == true
              @intercept = nil 
              instance_eval(&events[:intercept_end]) if events[:intercept_end].respond_to?(:call)
            end # @intercept.call(msg) == true
          else
            m = msg.strip
            @msg = txt
            @raw = msg
            @params = []

            if answers[m]
              ans = answers[m]
            elsif (match = answers.keys.select{|q| q.is_a?(Regexp) }.find{|q| msg.match(q) })
              # obviously this is slow - we can keep track of regexes on reloads
              @params      = *msg.match(match).to_a[1..-1]
              ans = answers[match]
            elsif self.class.answers[m]
              ans = self.class.answers[m]
            elsif (match = self.class.answers.keys.select{|q| q.is_a?(Regexp) }.find{|q| msg.match(q) })
              @params      = *msg.match(match).to_a[1..-1]
              ans = answers[match]
            else 
              ans = events[:no_answer]
              say("i couldn't find an answer to, '#{msg}'")
            end # @questions[m]
            
            @level += 1
            self.class.wrappers[:before][:each].each { |wrapper| instance_eval(&wrapper) }
            res = ans.is_a?(Proc) ? instance_eval(&ans) : nil
            if answers.empty? 
              #@level -= 1
              instance_eval &events[:branch_end]
            end # answers.empty?
            
            if res.is_a?(String)
              say(res)
              res = false
            end # res.is_a?(String)
            
            self.class.wrappers[:after][:each].each { |wrapper| instance_eval(&wrapper) }
            res == true ? end_conversation : continue_conversation
          end # !@intercept.nil?
        rescue Exception => e
          say("I've encountered an error: \n#{e}\n  #{e.backtrace.join("\n  ")}")
        end # begin
      end) #  |txt, msg|
    end # watch_proc

  end # class::Conversation
end # class::Starbot
