# frozen_string_literal: true

require 'rails_helper'

describe Api::V1::Collections do
  let(:valid_session) do
    env_secrets = Rails.application.config_for(:secrets)
    credentials = ActionController::HttpAuthentication::Basic.encode_credentials(
      env_secrets[:admin_user], env_secrets[:admin_password]
    )
    { 'HTTP_AUTHORIZATION' => credentials }
  end
  let(:valid_params) do
    { handle: 'agency_blogs', token: 'secret' }
  end
  let(:allow_updates) { true }
  let(:maintenance_message) { nil }
  let(:documents_index_name) { DocumentRepository.index_namespace('agency_blogs') }
  let(:document_repository) do
    DocumentRepository.new(index_name: documents_index_name)
  end

  before do
    I14y::Application.config.updates_allowed = allow_updates
    I14y::Application.config.maintenance_message = maintenance_message
  end

  after do
    I14y::Application.config.updates_allowed = true
  end

  describe 'POST /api/v1/collections' do
    context 'when successful' do
      before do
        clear_index(collections_index_name)
        post '/api/v1/collections', params: valid_params, headers: valid_session
      end

      it 'returns success message as JSON' do
        expect(response.status).to eq(201)
        expect(JSON.parse(response.body)).to match(
          hash_including('status' => 200,
                         'developer_message' => 'OK',
                         'user_message' => 'Your collection was successfully created.')
        )
      end

      it 'uses the collection handle as the Elasticsearch ID' do
        expect(ES.collection_repository.find('agency_blogs')).to be_present
      end

      it 'stores the appropriate fields in the Elasticsearch collection' do
        collection = ES.collection_repository.find('agency_blogs')
        expect(collection.token).to eq('secret')
        expect(collection.created_at).to be_an_instance_of(Time)
        expect(collection.updated_at).to be_an_instance_of(Time)
      end

      it_behaves_like 'a data modifying request made during read-only mode'
    end

    context 'when a required parameter is empty/blank' do
      before do
        invalid_params = {}
        post '/api/v1/collections', params: invalid_params, headers: valid_session
      end

      it 'returns failure message as JSON' do
        expect(response.status).to eq(400)
        expect(JSON.parse(response.body)).to match(
          hash_including('status' => 400,
                         'developer_message' => 'handle is missing, handle is empty, token is missing, token is empty')
        )
      end
    end

    context 'when handle uses illegal characters' do
      let(:invalid_params) do
        { handle: 'agency-blogs', token: 'secret' }
      end

      before do
        post '/api/v1/collections', params: invalid_params, headers: valid_session
      end

      it 'returns failure message as JSON' do
        expect(response.status).to eq(400)
        expect(JSON.parse(response.body)).to match(
          hash_including('status' => 400,
                         'developer_message' => 'handle is invalid')
        )
      end
    end

    context 'when authentication/authorization fails' do
      before do
        bad_credentials = ActionController::HttpAuthentication::Basic.encode_credentials 'nope', 'wrong'

        valid_session = { 'HTTP_AUTHORIZATION' => bad_credentials }
        post '/api/v1/collections', params: valid_params, headers: valid_session
      end

      it 'returns error message as JSON' do
        expect(response.status).to eq(400)
        expect(JSON.parse(response.body)).to match(
          hash_including('status' => 400,
                         'developer_message' => 'Unauthorized')
        )
      end
    end

    context 'when something terrible happens' do
      before do
        allow(Collection).to receive(:new) { raise_error(Exception) }
        post '/api/v1/collections', params: valid_params, headers: valid_session
      end

      it 'returns failure message as JSON' do
        expect(response.status).to eq(500)
        expect(JSON.parse(response.body)).to match(
          hash_including('status' => 500,
                         'developer_message' => "Something unexpected happened and we've been alerted.")
        )
      end
    end
  end

  describe 'DELETE /api/v1/collections/{handle}' do
    context 'when successful' do
      before do
        clear_index(collections_index_name)
        collection = Collection.new(id: 'agency_blogs', token: 'secret')
        ES.collection_repository.save(collection)
        delete '/api/v1/collections/agency_blogs', headers: valid_session
      end

      it 'returns success message as JSON' do
        expect(response.status).to eq(200)
        expect(JSON.parse(response.body)).to match(
          hash_including('status' => 200,
                         'developer_message' => 'OK',
                         'user_message' => 'Your collection was successfully deleted.')
        )
      end

      it 'deletes the collection' do
        expect(ES.collection_repository.exists?('agency_blogs')).to be_falsey
      end

      it_behaves_like 'a data modifying request made during read-only mode'
    end
  end

  describe 'GET /api/v1/collections/{handle}' do
    context 'when successful' do
      before do
        clear_index(collections_index_name)
        post '/api/v1/collections', params: valid_params, headers: valid_session
        clear_index(documents_index_name)
      end

      let(:datetime) { DateTime.now.utc }
      let(:hash1) do
        {
          _id: 'a1',
          language: 'en',
          title: 'title 1 common content',
          description: 'description 1 common content',
          created: Time.zone.now,
          path: 'http://www.agency.gov/page1.html'
        }
      end
      let(:hash2) do
        {
          _id: 'a2',
          language: 'en',
          title: 'title 2 common content',
          description: 'description 2 common content',
          created: Time.zone.now,
          path: 'http://www.agency.gov/page2.html'
        }
      end

      it 'returns success message with Collection stats as JSON' do
        document_repository.save(Document.new(hash1))
        document_repository.save(Document.new(hash2))
        document_repository.refresh_index!
        get '/api/v1/collections/agency_blogs', headers: valid_session
        expect(response.status).to eq(200)
        expect(JSON.parse(response.body)).to match(
          hash_including('status' => 200,
                         'developer_message' => 'OK',
                         'collection' => { 'document_total' => 2,
                                           'last_document_sent' => an_instance_of(String),
                                           'token' => 'secret',
                                           'id' => 'agency_blogs',
                                           'created_at' => an_instance_of(String),
                                           'updated_at' => an_instance_of(String) })
        )
      end
    end
  end

  describe 'GET /api/v1/collections/search' do
    before do
      clear_index(collections_index_name)
      post '/api/v1/collections', params: valid_params, headers: valid_session
      clear_index(documents_index_name)
    end

    it 'uses the appropriate parameters for the DocumentSearch' do
      valid_params = {
        language: 'en',
        query: 'common content',
        handles: 'agency_blogs',
        sort_by_date: 1,
        min_timestamp: '2013-02-27T10:00:00Z',
        max_timestamp: '2013-02-27T10:01:00Z',
        offset: 2**32,
        size: 3,
        tags: 'Foo, Bar blat',
        ignore_tags: 'ignored',
        include: 'title,description'
      }
      expected_params = Hashie::Mash.new(
        'language' => :en,
        'query' => 'common content',
        'handles' => %w[agency_blogs],
        'offset' => 2**32,
        'size' => 3,
        'sort_by_date' => true,
        'min_timestamp' => DateTime.parse('2013-02-27T10:00:00Z'),
        'max_timestamp' => DateTime.parse('2013-02-27T10:01:00Z'),
        'tags' => ['foo', 'bar blat'],
        'ignore_tags' => ['ignored'],
        'include' => %w[title description]
      )
      allow(DocumentSearch).to receive(:new)
      get '/api/v1/collections/search', params: valid_params, headers: valid_session
      expect(DocumentSearch).to have_received(:new).with(expected_params)
    end

    context 'when results exist' do
      before do
        document_repository.save(Document.new(hash1))
        document_repository.save(Document.new(hash2))
        document_repository.refresh_index!
        valid_params = { language: 'en', query: 'common contentx', handles: 'agency_blogs' }
        get '/api/v1/collections/search', params: valid_params, headers: valid_session
      end

      let(:datetime) { DateTime.now.utc.to_s }
      let(:hash1) do
        { _id: 'a1',
          language: 'en',
          title: 'title 1 common content',
          description: 'description 1 common content',
          content: 'content 1 common content',
          created: datetime,
          path: 'http://www.agency.gov/page1.html',
          promote: true,
          updated: datetime,
          updated_at: datetime }
      end
      let(:hash2) do
        { _id: 'a2',
          language: 'en',
          title: 'title 2 common content',
          description: 'description 2 common content',
          content: 'other unrelated stuff',
          created: datetime,
          path: 'http://www.agency.gov/page2.html',
          promote: false,
          tags: 'tag1, tag2',
          updated_at: datetime }
      end

      describe 'status' do
        subject { response.status }

        it { is_expected.to eq(200) }
      end

      describe 'body' do
        let(:body) { JSON.parse(response.body) }
        let(:result1) do
          {
            'language' => 'en',
            'created' => datetime,
            'path' => 'http://www.agency.gov/page1.html',
            'title' => 'title 1 common content',
            'description' => 'description 1 common content',
            'content' => 'content 1 common content',
            'changed' => datetime
          }
        end
        let(:result2) do
          {
            'language' => 'en',
            'created' => datetime,
            'path' => 'http://www.agency.gov/page2.html',
            'title' => 'title 2 common content',
            'description' => 'description 2 common content',
            'changed' => datetime
          }
        end

        it 'returns highlighted JSON search results' do
          expect(body).to match(hash_including('results' => [result1, result2]))
        end

        describe 'metadata' do
          let(:metadata) { body['metadata'] }
          let(:suggestion_hash) do
            { 'text' => 'common content',
              'highlighted' => 'common content' }
          end

          it 'returns highlighted JSON suggestion' do
            expect(metadata['suggestion']).to match(hash_including(suggestion_hash))
          end

          it 'returns a non-zero results total' do
            expect(metadata['total']).to be > 0
          end

          it 'returns aggregations' do
            expect(metadata['aggregations']).not_to be_empty
          end
        end
      end
    end

    context 'when no results exist' do
      before do
        valid_params = { language: 'en', query: 'no hits', handles: 'agency_blogs' }
        get '/api/v1/collections/search', params: valid_params, headers: valid_session
      end

      describe 'status' do
        subject { response.status }

        it { is_expected.to eq(200) }
      end

      describe 'body' do
        let(:body) { JSON.parse(response.body) }

        it 'returns an empty results array' do
          expect(body).to match(hash_including('results' => []))
        end

        describe 'metadata' do
          let(:metadata) { body['metadata'] }

          it 'returns zero results total' do
            expect(metadata['total']).to eq(0)
          end

          it 'returns nil suggestion' do
            expect(metadata['suggestion']).to be_nil
          end

          it 'returns empty aggregations' do
            expect(metadata['aggregations']).to be_empty
          end
        end
      end
    end

    context 'when missing required params' do
      before do
        invalid_params = {}
        get '/api/v1/collections/search', params: invalid_params, headers: valid_session
      end

      it 'returns error message as JSON' do
        expect(response.status).to eq(400)
        expect(JSON.parse(response.body)).to match(
          hash_including('status' => 400,
                         'developer_message' => 'handles is missing, handles is empty')
        )
      end
    end

    context 'when searching across one or more collection handles that do not exist' do
      let(:bad_handle_params) do
        { language: 'en', query: 'foo', handles: 'agency_blogs,missing' }
      end

      before do
        clear_index(collections_index_name)
        collection = Collection.new(id: 'agency_blogs', token: 'secret')
        ES.collection_repository.save(collection)
        get '/api/v1/collections/search', params: bad_handle_params, headers: valid_session
      end

      it 'returns error message as JSON' do
        expect(response.status).to eq(400)
        expect(JSON.parse(response.body)).to match(
          hash_including('error' => 'Could not find all the specified collection handles')
        )
      end
    end
  end
end
