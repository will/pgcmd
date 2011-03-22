require 'rubygems'
require 'rspec'
require './pg'

include Heroku::Command

describe Pg::Resolver do
  context "pass in *_URL" do
    let(:r) { Pg::Resolver.new "HEROKU_POSTGRESQL_SOME_URL", "HEROKU_POSTGRESQL_SOME_URL" => 'something'}

    it 'should warn to not add in _URL, and proceed without it' do
      r.message.should == "HEROKU_POSTGRESQL_SOME_URL is deprecated, please use HEROKU_POSTGRESQL_SOME\nusing SOME"
    end

    it 'should have [] access' do
      r[:url].should == 'something'
      r[:name].should == 'SOME'
    end
  end

  context "only shared database" do
     let(:config) do
       { 'DATABASE_URL'        => 'postgres://shared',
         'SHARED_DATABASE_URL' => 'postgres://shared' }
    end

    it 'returns the shared url when asked for DATABASE' do
      r = Pg::Resolver.new("DATABASE", config)
      r.url.should == 'postgres://shared'
      r.message.should == "using SHARED_DATABASE"
    end

    it 'reutrns the shared url when asked for SHARED_DATABASE' do
      r = Pg::Resolver.new("SHARED_DATABASE", config)
      r.url.should == 'postgres://shared'
      r.message.should_not be
    end
  end

  context 'only dedicated database' do
    let(:config) do
      { 'DATABASE_URL' => 'postgres://dedicated',
        'HEROKU_POSTGRESQL_PERIWINKLE_URL' => 'postgres://dedicated' }
    end

    it 'returns the dedicated url when asked for DATABASE' do
      r = Pg::Resolver.new('DATABASE', config)
      r.url.should == 'postgres://dedicated'
      r.message.should == 'using PERIWINKLE'
    end

    it 'returns the dedicated url when asked for COLOR' do
      r = Pg::Resolver.new('PERIWINKLE', config)
      r.url.should == 'postgres://dedicated'
      r.message.should_not be
    end

    it 'returns the dedicated url when asked for H_PG_COLOR' do
      r = Pg::Resolver.new('HEROKU_POSTGRESQL_PERIWINKLE', config)
      r.url.should == 'postgres://dedicated'
      r.message.should == 'using PERIWINKLE'
    end

    it 'returns the dedicated url when asked for H_PG_COLOR_URL' do
      r = Pg::Resolver.new('HEROKU_POSTGRESQL_PERIWINKLE_URL', config)
      r.url.should == 'postgres://dedicated'
      r.message.should =~ /deprecated/
      r.message.should =~ /using PERIWINKLE/
    end
  end

  context 'dedicated databases and shared database' do
    let(:config) do
      { 'DATABASE_URL' => 'postgres://red',
        'SHARED_DATABASE_URL' => 'postgres://shared',
        'HEROKU_POSTGRESQL_PERIWINKLE_URL' => 'postgres://pari',
        'HEROKU_POSTGRESQL_RED_URL' => 'postgres://red' }
    end

    it 'maps default correctly' do
      r = Pg::Resolver.new('DATABASE', config)
      r.url.should == 'postgres://red'
    end

    it 'warns if DATABASE_URL is wrong' do
      r = Pg::Resolver.new('DATABASE', config.merge!({"DATABASE_URL" => "foo"}))
      r.message.should =~ /DATABASE_URL does not match/
    end

    it 'is able to get the non default database' do
      r = Pg::Resolver.new('PERIWINKLE', config)
      r.url.should == 'postgres://pari'
    end

    it 'returns all with Resolver.all' do
      Pg::Resolver.all(config).should =~ [
        {:name => 'SHARED_DATABASE', :pretty_name => 'SHARED_DATABASE', :url => 'postgres://shared', :default => false},
        {:name => 'PERIWINKLE',      :pretty_name => 'PERIWINKLE',      :url => 'postgres://pari',   :default => false},
        {:name => 'RED',     :pretty_name => 'RED (DATABASE_URL)',      :url => 'postgres://red',    :default => true}
      ]
    end
  end
end
