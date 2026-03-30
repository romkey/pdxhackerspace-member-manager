require 'test_helper'

module TextFragments
  class SyncFromUrlTest < ActiveSupport::TestCase
    ResponseStub = Struct.new(:success, :status, :body) do
      def success?
        success
      end
    end

    def stub_response(success, status, body)
      ResponseStub.new(success, status, body)
    end

    setup do
      @fragment = TextFragment.create!(key: 'sync_test_fragment', title: 'Sync Test', content: 'old')
    end

    teardown do
      @fragment.destroy
    end

    test 'raises when source_url is blank' do
      @fragment.update!(source_url: '')
      error = assert_raises(SyncFromUrl::Error) { SyncFromUrl.call(@fragment) }
      assert_match(/no source url/i, error.message)
    end

    test 'fetches content and updates fragment' do
      @fragment.update!(source_url: 'https://example.com/')

      SyncFromUrl.call(@fragment) do |fetched_url|
        assert_equal 'https://example.com/', fetched_url
        stub_response(true, 200, "<p>hello</p>\n")
      end

      assert_equal "<p>hello</p>\n", @fragment.reload.content
    end

    test 'uses normalized URL for GitHub blob links' do
      @fragment.update!(source_url: 'https://github.com/foo/bar/blob/main/x.txt')

      SyncFromUrl.call(@fragment) do |fetched_url|
        assert_equal 'https://raw.githubusercontent.com/foo/bar/main/x.txt', fetched_url
        stub_response(true, 200, 'file body')
      end

      assert_equal 'file body', @fragment.reload.content
    end
  end
end
