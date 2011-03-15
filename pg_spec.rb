require 'rubygems'
require 'rspec'
require 'init'

include Heroku::Command

describe Pg, '#resolve' do
  let(:pg) do
    pg = Pg.new
    pg.stub!(:heroku).and_return(mock(:heroku))
    pg
  end

  let(:heroku) { pg.heroku }

  def should_display(msg)
    heroku.should_receive(:display) { |arg| arg.should =~ /#{msg}/ }
  end

# RED
# HEROKU_POSTGRESQL_RED => SWITCH TO RED
# HEROKU_POSTGRESQL_RED_URL => warn, switch to RED
# DATABSE_URL => warn, switch to database
#
  context "pass in *_URL" do
    it 'should warn to not add in _URL, and proceed without it' do
      pg.stub!(:config_vars).and_return({"SOME_URL" => 'something'})
      should_display("SOME_URL is deprecated, please use SOME")
      pg.resolve("SOME_URL").should == 'something'
    end
  end

  context "only shared database" do
    before(:each) do
      pg.stub!(:config_vars).and_return({
        'DATABASE_URL' => 'postgres://shared',
        'SHARED_DATABASE_URL' => 'postgres://shared',
      })
    end

    it 'returns the shared url when asked for DATABASE' do
      should_display "SHARED_DATABASE_URL"
      pg.resolve("DATABASE").should == 'postgres://shared'
    end

    it 'reutrns the shared url when asked for SHARED_DATABASE' do
      heroku.should_not_receive(:display)
      pg.resolve("SHARED_DATABASE").should == 'postgres://shared'
    end
  end
end
