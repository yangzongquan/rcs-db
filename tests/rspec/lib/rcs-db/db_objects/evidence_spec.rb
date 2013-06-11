require 'spec_helper'
require_db 'db_layer'
require_db 'grid'

describe Evidence do

  use_db
  silence_alerts

  describe '#common_filter' do

    # "params" could be:

    # default
    # {"filter"=>
    # "{\"from\":\"24h\",\"target\":\"4f86902a2afb6512a700006f\",\"agent\":\"5008225c2afb654a4f003b9b\",\"date\":\"dr\"}"}

    # unchecking "Received"
    # {"filter"=>
    # "{\"from\":0,\"target\":\"4f86902a2afb6512a700006f\",\"to\":0,\"agent\":\"5008225c2afb654a4f003b9b\",\"date\":\"da\"}"}

    # checking some type in the "type" column
    # {"filter"=>
    # "{\"agent\":\"5008225c2afb654a4f003b9b\",\"from\":0,\"target\":\"4f86902a2afb6512a700006f\",\"to\":0,\"date\":\"da\",
    # \"type\":[\"device\",\"file\",\"keylog\"]}"}

    # writing something in the "info" text area
    # {"filter"=>
    # "{\"info\":\"pippo pluto\",\"agent\":\"5008225c2afb654a4f003b9b\",\"from\":0,\"target\":\"4f86902a2afb6512a700006f\",\"to\":0,
    # \"date\":\"da\",\"type\":[\"device\",\"file\",\"keylog\"]}"}

    let(:operation) { Item.create!(name: 'op1', _kind: :operation, path: [], stat: ::Stat.new) }

    let(:target) { Item.create!(name: 'target1', _kind: :target, path: [operation.id], stat: ::Stat.new) }

    let(:filter) { {"from" => "24h", "target" => "a_target_id", "agent" => "an_agent_id"} }

    let(:params) { {"filter" => filter} }

    let(:params_with_invalid_filter) { {'filter' => 'invalid_json'} }

    let :filter_hash do
      params['filter']['target'] = target.id
      described_class.common_filter(params)[1]
    end

    it 'raises an error if the "filter" could not be parsed to JSON' do
      expect{ described_class.common_filter(params_with_invalid_filter) }.to raise_error JSON::ParserError
    end

    context 'when the target cannot be found' do

      it 'returns nil without raising errors' do
        expect(described_class.common_filter params).to be_nil
      end
    end

    context 'when the target exists' do

      #build the target and puts its id in the 'filter' hash
      before { params['filter']['target'] = target.id }

      it 'returns the target' do
        ary = described_class.common_filter params
        expect(ary.last).to eql target
      end
    end

    context 'when an hash without the "filter" key is passed' do

      it 'returns nil without raising errors' do
        expect(described_class.common_filter({})).to be_nil
      end
    end

    context 'when the filter does not have a "date" attribute' do

      # note: dr stans for date received
      let(:filter) { {"from" => "24h", "target" => "a_target_id", "agent" => "an_agent_id", "date" => "dr"} }

      it 'uses the given attribute for a filter' do
        filter_on_da = filter_hash.select { |key| key.respond_to?(:name) and key.name == :dr }
        expect(filter_on_da).not_to be_empty
      end
    end

    it 'uses the "da" attribute' do
      filter_on_da = filter_hash.select { |key| key.respond_to?(:name) and key.name == :da }
      expect(filter_on_da).not_to be_empty
    end

    it 'contains the agent id (even if the agent is missing in the db)' do
      expect(filter_hash[:aid]).to eql 'an_agent_id'
    end

    context 'when the "info" is a string' do

      let(:filter) { {"from" => "24h", "target" => "a_target_id", "agent" => "an_agent_id", "info" => "asd lol"} }

      it 'return filter for it' do
        filter_on_kw = filter_hash.select { |key, value| value.inspect.include?('asd') }
        expect(filter_on_kw).to have_key '$or'
        expect(filter_on_kw).not_to be_empty
      end
    end

    context 'when the "info" is an array of strings' do

      let(:filter) { {"from" => "24h", "target" => "a_target_id", "agent" => "an_agent_id", "info" => %[asd lol]} }

      it 'return filter for it' do
        filter_on_kw = filter_hash.select { |key, value| value.inspect.include?('asd') }
        expect(filter_on_kw).to have_key '$or'
        expect(filter_on_kw).not_to be_empty
      end
    end

    context 'when "note" is present in the filters' do

      let(:filter) { {"from" => "24h", "target" => "a_target_id", "agent" => "an_agent_id", "info" => %[asd], "note" => %w[lol]} }

      # TODO: this is currenty a bug
      it 'does not overwrites the filters for "info"' do
        filter_on_kw = filter_hash.select { |key, value| value.inspect.include?('asd') }
        expect(filter_on_kw).to have_key '$or'
        expect(filter_on_kw).not_to be_empty
        expect(filter_on_kw.inspect).to include 'lol'
      end
    end
  end

  describe '#filter_for_keywords' do

    let(:info) { ['john dorian skype'] }

    let(:filter_hash) { {} }

    it 'adds to the filter_hash a selector on the :kw attribute' do
      described_class.filter_for_keywords info, filter_hash
      selector = filter_hash.keys.first
      expect(selector).to eql '$or'
      expect(filter_hash[selector]).to eql [{"kw"=>{"$all"=>["dorian", "john", "skype"]}}]
    end

    context 'when the "info" contains more than one string' do

      let(:info) { %w[john dorian skype] }

      it 'adds to the filter_hash a selector on the :kw attribute' do
        described_class.filter_for_keywords info, filter_hash
        expect(filter_hash).not_to be_empty
      end
    end

    context 'when "info" contains "lat", "lon" and "r"' do

      let(:info) { ["to:prova@gmail.com,lat:30,lon:30,r:100"] }

      it 'does not inclue lat, lon and r in the filter_hash' do
        described_class.filter_for_keywords info, filter_hash
        expect(filter_hash.size).to eql 2
      end
    end
  end

  describe '#filter_for_position' do

    context 'when "info" contains "lat", "lon" and "r"' do

      let(:info) { ["to:prova@gmail.com,lat:30,lon:30,r:100"] }

      let(:filter_hash) { {} }

      # let!(:target) { factory_create(:target) }

      # before do
      #   factory_create(:position_evidence, target: target, latitude: 30.0, longitude: 30.0)
      #   factory_create(:position_evidence, target: target, latitude: 1.0, longitude: 1.0)
      # end

      it 'adds a $near filter to search for a position evidence' do
        described_class.filter_for_position info, filter_hash
        expect(filter_hash['data.position']).not_to be_empty
      end
    end
  end
end
