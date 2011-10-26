require File.join(File.dirname(__FILE__), "spec_helper.rb")

describe "conversation builder" do
  before :all do
    @bot = Starbot.new("spec")
    
    @convo_def = Proc.new  do
      say "the weather's fine"

      default_answer { end_conversation }               # unrecognized responses stop the conversation
      answer "what's the temperature" do
        say "it's 26C"                                  # answers and goes back a level
      end
      answer "what's the humidity" do
        say "it's 78%"                                  # answers and goes back a level
      end
      answer "do I need an umbrella?" do
        say "nah, it's sunny now and won't rain today"  # answers and goes back a level
      end

      answer "what about tomorrow?" do
        answer "what will the temperature be" do
          say "it'll be 24C"                            # answers and goes back a level
        end
        answer "what will the humidity be" do
          say "it'll be 100%"                           # answers and goes back a level
        end
        answer "do I need an umbrella?" do
          say "it's going to rain, so yeah, you do."    # answers and goes back a level
        end
      end
    end # conversation("how's the weather")
  end # :all
  
  it "should build a new class" do
    expect {
      @bot.conversation("how's the weather", &@convo_def)
    }.to change { Starbot::Conversation.constants.count }.by(1)
  end # should build a new class
  it "should return the class it builds" do
    @bot.conversation("how's the weather", &@convo_def).should be_a Module
  end # should return the class it builds
  it "should build a class that inherits from Starbot::Conversation" do
    (@bot.conversation("how's the weather", &@convo_def) < Starbot::Conversation).should be true
  end # should build a class that inherits from Starbot::Conversation
  it "should build separate classes for Procs that are defined in the same place" do
    @bot.conversation("how's the weather", &@convo_def).to_s[0..-2].should == @bot.conversation("how's the weather", &@convo_def).to_s[0..-2]
    @bot.conversation("how's the weather", &@convo_def).to_s[-1].to_i.should == @bot.conversation("how's the weather", &@convo_def).to_s[-1].to_i - 1
  end # should build separate classes for Procs that are defined in the same place
end # conversation builder