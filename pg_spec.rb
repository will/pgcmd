require 'rubygems'
require 'rspec'
require 'init'

include Heroku::Command

describe Pg::Resolver, '#resolve' do
# RED
# HEROKU_POSTGRESQL_RED => SWITCH TO RED
# HEROKU_POSTGRESQL_RED_URL => warn, switch to RED
# DATABSE_URL => warn, switch to database
#
  context "pass in *_URL" do
    it 'should warn to not add in _URL, and proceed without it' do
      r = Pg::Resolver.new "SOME_URL" => 'something'
      r.resolve("SOME_URL").should == 'something'
      r.message.should == "SOME_URL is deprecated, please use SOME"
    end
  end

  context "only shared database" do
     let(:r) do
       Pg::Resolver.new({
        'DATABASE_URL' => 'postgres://shared',
        'SHARED_DATABASE_URL' => 'postgres://shared',
      })
    end

    it 'returns the shared url when asked for DATABASE' do
      r.resolve("DATABASE").should == 'postgres://shared'
      r.message.should == "using SHARED_DATABASE_URL"
    end

    it 'reutrns the shared url when asked for SHARED_DATABASE' do
      r.resolve("SHARED_DATABASE").should == 'postgres://shared'
      r.message.should_not be
    end
  end
end
