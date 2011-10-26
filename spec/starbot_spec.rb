require File.join(File.dirname(__FILE__), "spec_helper.rb")

describe "git hub integration" do
  it "should process a github post-receive" do
    pending
    payload = 'payload={"before":"5aef35982fb2d34e9d9d4502f6ede1072793222d","repository":{"url":"http://github.com/defunkt/github","name":"github","description":"Youre lookin at it.","watchers":5,"forks":2,"private":1,"owner":{"email":"chris@ozmm.org","name":"defunkt"}},"commits":[{"id":"41a212ee83ca127e3c8cf465891ab7216a705f59","url":"http://github.com/defunkt/github/commit/41a212ee83ca127e3c8cf465891ab7216a705f59","author":{"email":"chris@ozmm.org","name":"Chris Wanstrath"},"message":"okay i give in","timestamp":"2008-02-15T14=>57=>17-08=>00","added":["filepath.rb"]},{"id":"de8251ff97ee194a289832576287d6f8ad74e3d0","url":"http://github.com/defunkt/github/commit/de8251ff97ee194a289832576287d6f8ad74e3d0","author":{"email":"chris@ozmm.org","name":"Chris Wanstrath"},"message":"update pricing a tad","timestamp":"2008-02-15T14:36:34-08:00"}],"after":"de8251ff97ee194a289832576287d6f8ad74e3d0","ref":"refs/heads/master"}'
  end # it should process a github post-receive  
end # "git hub integration"

describe "default room" do
  before(:all) do
    @starbot = Starbot.new("starbot").load_answers(File.dirname(__FILE__) + "/starbot.answers")
    @starbot.log.level = Logger::ERROR
  end
  
  specify 'the default room should stay the default room' do
    callcount = {:other => 0, :default => 0 }
    @starbot.answer('default room') do
      callcount[:default] += 1
      say("answer in default room") 
    end
    @starbot.answer('other room') do
      callcount[:other] += 1
      say("answer in other room") 
    end
    
    defroom     = nil
    othroom     = nil

    @starbot.on(:sayto) {|a,m| defroom = m }

    @starbot.route('default room')
    defroom.should == 'answer in default room'

    @starbot.context do |ctx|
      ctx.on(:sayto) {|a,m| othroom = m}
      ctx.route('other room')
    end #  |ctx|

    @starbot.route('default room')
    
    callcount[:default].should == 2
    callcount[:other].should == 1
    defroom.should == 'answer in default room'
    othroom.should == 'answer in other room'
  end # the default room should stay the default room
  
  specify 'when a string is returned from a helper it should be said'
  
  specify "starbot's answers should be thread-safe" do
    @starbot.answer('thread 1') do
      sleep 0.15
      say("thread 1") 
    end
    
    @starbot.answer('thread 2') do
      sleep 0.25
      say("thread 2")
    end
    
    t1chan = nil
    t2chan = nil
    
    Thread.new do |t1|
      @starbot.context do |ctx| 
        ctx.on(:sayto) { |a,m| t1chan = m }
        ctx.route('thread 1')
      end
    end #  |t1|
    
    @starbot.context do |ctx| 
      ctx.on(:sayto) { |a,m| t2chan = m } 
      ctx.route('thread 2')
    end
    
    sleep 0.5
    
    t1chan.should == "thread 1"
    t2chan.should == "thread 2"
  end # starbot's answers should be thread-safe
  
  specify 'reloading answers should not duplicate scheduled jobs' do
    expect {
      @starbot.reload_answers
    }.to_not change { @starbot.scheduled.count }
  end # reloading answers should not duplicate scheduled jobs
  specify 'reload answers should not duplicate helpers' do
    expect {
      @starbot.reload_answers
    }.to_not change { @starbot.helpers.count }
  end # reload answers should not duplicate helpers
  
end # default room
