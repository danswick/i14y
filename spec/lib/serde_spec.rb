# frozen_string_literal: true

require 'rails_helper'

describe Serde do
  describe '.serialize_hash' do
    subject(:serialize_hash) do
      described_class.serialize_hash(original_hash, 'en')
    end

    let(:original_hash) do
      ActiveSupport::HashWithIndifferentAccess.new(
        { 'title' => 'my title',
          'description' => 'my description',
          'content' => 'my content',
          'path' => 'http://www.foo.gov/bar.html',
          'promote' => false,
          'tags' => 'this that',
          'searchgov_custom1' => 'this, custom, content',
          'searchgov_custom2' => 'that custom, content',
          'searchgov_custom3' => '123',
          'created' => '2018-01-01T12:00:00Z',
          'changed' => '2018-02-01T12:00:00Z',
          'created_at' => '2018-01-01T12:00:00Z',
          'updated_at' => '2018-02-01T12:00:00Z' }
      )
    end

    it 'stores the language fields with the language suffix' do
      expect(serialize_hash).to match(hash_including(
        { 'title_en' => 'my title',
          'description_en' => 'my description',
          'content_en' => 'my content' }
      ))
    end

    it 'stores tags as an array' do
      expect(serialize_hash).to match(hash_including(
        { 'tags' => ['this that'] }
      ))
    end

    it 'stores searchgov_custom fields as arrays' do
      expect(serialize_hash).to match(hash_including(
        { 'searchgov_custom1' => ['this', 'custom', 'content'],
          'searchgov_custom2' => ['that custom', 'content'],
          'searchgov_custom3' => ['123'] }
      ))
    end

    it 'updates the updated_at value' do
      expect(serialize_hash[:updated_at]).to be > 1.second.ago
    end

    context 'when language fields contain HTML/CSS' do
      let(:html) do
        <<~HTML
          <div style="height: 100px; width: 100px;"></div>
          <p>hello & goodbye!</p>
        HTML
      end

      let(:original_hash) do
        ActiveSupport::HashWithIndifferentAccess.new(
          title: '<b><a href="http://foo.com/">foo</a></b><img src="bar.jpg">',
          description: html,
          content: "this <b>is</b> <a href='http://gov.gov/url.html'>html</a>"
        )
      end

      it 'sanitizes the language fields' do
        expect(serialize_hash).to match(hash_including(
          title_en: 'foo',
          description_en: 'hello & goodbye!',
          content_en: 'this is html'
        ))
      end
    end

    context 'when the tags are a comma-delimited list' do
      let(:original_hash) do
        { tags: 'this, that' }
      end

      it 'converts the tags to an array' do
        expect(serialize_hash).to match(hash_including(tags: %w[this that]))
      end
    end
  end

  describe '.deserialize_hash' do
    subject(:deserialize_hash) do
      described_class.deserialize_hash(original_hash, :en)
    end

    let(:original_hash) do
      ActiveSupport::HashWithIndifferentAccess.new(
        { 'created_at' => '2018-08-09T21:36:50.087Z',
          'updated_at' => '2018-08-09T21:36:50.087Z',
          'path' => 'http://www.foo.gov/bar.html',
          'language' => 'en',
          'created' => '2018-08-09T19:36:50.087Z',
          'updated' => '2018-08-09T14:36:50.087-07:00',
          'changed' => '2018-08-09T14:36:50.087-07:00',
          'promote' => true,
          'tags' => 'this that',
          'title_en' => 'my title',
          'description_en' => 'my description',
          'content_en' => 'my content',
          'basename' => 'bar',
          'extension' => 'html',
          'url_path' => '/bar.html',
          'domain_name' => 'www.foo.gov' }
      )
    end
    let(:language_field_keys) { %i[title description content] }

    it 'removes the language suffix from the text fields' do
      expect(deserialize_hash).to eq(
        { 'created_at' => '2018-08-09T21:36:50.087Z',
          'updated_at' => '2018-08-09T21:36:50.087Z',
          'path' => 'http://www.foo.gov/bar.html',
          'language' => 'en',
          'created' => '2018-08-09T19:36:50.087Z',
          'title' => 'my title',
          'description' => 'my description',
          'content' => 'my content',
          'updated' => '2018-08-09T14:36:50.087-07:00',
          'changed' => '2018-08-09T14:36:50.087-07:00',
          'promote' => true,
          'tags' => 'this that' }
      )
    end
  end

  describe '.uri_params_hash' do
    subject(:result) { described_class.uri_params_hash(path) }

    let(:path) { 'https://www.agency.gov/directory/page1.html' }

    it 'computes basename' do
      expect(result[:basename]).to eq('page1')
    end

    it 'computes filename extension' do
      expect(result[:extension]).to eq('html')
    end

    context 'when the extension has uppercase characters' do
      let(:path) { 'https://www.agency.gov/directory/PAGE1.PDF' }

      it 'computes a downcased version of filename extension' do
        expect(result[:extension]).to eq('pdf')
      end
    end

    context 'when there is no filename extension' do
      let(:path) { 'https://www.agency.gov/directory/page1' }

      it 'computes an empty filename extension' do
        expect(result[:extension]).to eq('')
      end
    end

    it 'computes url_path' do
      expect(result[:url_path]).to eq('/directory/page1.html')
    end

    it 'computes domain_name' do
      expect(result[:domain_name]).to eq('www.agency.gov')
    end
  end
end
