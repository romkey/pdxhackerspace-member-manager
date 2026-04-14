require 'test_helper'

class AiProviderTest < ActiveSupport::TestCase
  test 'seed_defaults creates expected providers' do
    AiProvider.delete_all

    AiProvider.seed_defaults!

    names = AiProvider.order(:name).pluck(:name)
    assert_equal %w[ChatGPT Claude Copilot Gemini Openrouter Perplexity], names
  end
end
