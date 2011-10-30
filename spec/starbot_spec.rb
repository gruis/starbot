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
  
  specify 'send responses to the right contact and room' do
    @starbot.answer('default room') { say("answer in default room"); nil }
    @starbot.answer('other room') { say("answer in other room"); nil }
    
    responses   = {'roomA' => {:msg => nil, :cnt => 0}, 'roomB' => {:msg => nil, :cnt => 0}}
    @starbot.on(:sayto) do |a,m| 
      responses[a.to_s][:msg] = m
      responses[a.to_s][:cnt] += 1
    end

    msgA = ::Starbot::Msg.new('default room', @starbot.contact_list.create('userA', 'userA'), Time.new,
                                              @starbot.room_list.create('roomA', 'roomA', 'userA', Time.new) )
    msgB = ::Starbot::Msg.new('other room', @starbot.contact_list.create('userB', 'userB'), Time.new,
                                            @starbot.room_list.create('roomB', 'roomB', 'userB', Time.new) )

    @starbot.route(msgA.txt, msgA)
    responses["roomA"][:msg].should == 'answer in default room'

    @starbot.route(msgA.txt, msgA)
    @starbot.route(msgB.txt, msgB)
    
    responses['roomA'][:cnt].should == 2
    responses['roomB'][:cnt].should == 1
    responses['roomA'][:msg].should == 'answer in default room'
    responses['roomB'][:msg].should == 'answer in other room'
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
    
    responses   = {}
    @starbot.on(:sayto) { |a,m| responses[a.to_s] = m }
    
    msgA = ::Starbot::Msg.new('thread 1', @starbot.contact_list.create('userA', 'userA'), Time.new,
                                              @starbot.room_list.create('roomA', 'roomA', 'userA', Time.new) )
    msgB = ::Starbot::Msg.new('thread 2', @starbot.contact_list.create('userB', 'userB'), Time.new,
                                            @starbot.room_list.create('roomB', 'roomB', 'userB', Time.new) )
    Thread.new { |t1| @starbot.route(msgA) }
    @starbot.route(msgB)
    
    sleep 0.5
    
    responses['roomA'].should == 'thread 1'
    responses['roomB'].should == 'thread 2'
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
