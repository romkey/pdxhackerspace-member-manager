require 'test_helper'

class InterestTest < ActiveSupport::TestCase
  # Validations

  test 'valid with a unique name' do
    interest = Interest.new(name: 'Robotics')
    assert_predicate interest, :valid?
  end

  test 'invalid without a name' do
    interest = Interest.new(name: '')
    assert_not interest.valid?
    assert_includes interest.errors[:name], "can't be blank"
  end

  test 'invalid with a duplicate name (case-insensitive)' do
    # 'Electronics' already exists via fixtures
    duplicate = Interest.new(name: 'electronics')
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], 'has already been taken'
  end

  test 'strips whitespace from name before save' do
    interest = Interest.create!(name: '  Soldering  ')
    assert_equal 'Soldering', interest.name
  end

  # Scopes

  test 'alphabetical scope orders by name' do
    names = Interest.alphabetical.pluck(:name)
    assert_equal names, names.sort
  end

  test 'by_popularity orders by member count descending' do
    # electronics and programming are both selected by users(:one);
    # electronics is also selected by users(:two), so it has 2 members
    ordered = Interest.by_popularity.pluck(:name)
    electronics_index  = ordered.index('Electronics')
    programming_index  = ordered.index('Programming')
    woodworking_index  = ordered.index('Woodworking')

    assert electronics_index < programming_index,
           'Electronics (2 members) should appear before Programming (1 member)'
    assert_includes ordered, woodworking_index.to_i >= 0 ? 'Woodworking' : 'Woodworking'
  end

  # suggested class method

  test 'suggested returns up to the requested limit' do
    result = Interest.suggested(limit: 3)
    assert result.size <= 3
  end

  test 'suggested returns all interests when fewer than limit exist' do
    result = Interest.suggested(limit: 100)
    assert_equal Interest.count, result.size
  end

  test 'suggested excludes the given ids' do
    excluded = interests(:electronics)
    result   = Interest.suggested(limit: 20, exclude_ids: [excluded.id])
    assert_not_includes result.map(&:id), excluded.id
  end

  test 'suggested returns at most limit results when many interests exist' do
    10.times { |i| Interest.create!(name: "Auto-generated #{i}") }
    result = Interest.suggested(limit: 5)
    assert_equal 5, result.size
  end

  # seeded / needs_review flags

  test 'seeded? returns false when no interests are seeded' do
    assert_not Interest.seeded?
  end

  test 'seeded? returns true once a seeded interest exists' do
    Interest.create!(name: 'Seeded One', seeded: true)
    assert Interest.seeded?
  end

  test 'seeded_set scope returns only seeded interests' do
    Interest.create!(name: 'Seeded Two', seeded: true)
    Interest.create!(name: 'Unseeded',   seeded: false)
    seeded_names = Interest.seeded_set.pluck(:name)
    assert_includes seeded_names, 'Seeded Two'
    assert_not_includes seeded_names, 'Unseeded'
  end

  test 'needs_review scope returns only interests flagged for review' do
    Interest.create!(name: 'Pending Review', needs_review: true)
    review_names = Interest.needs_review.pluck(:name)
    assert_includes review_names, 'Pending Review'
    # Fixture interests default to needs_review: false
    assert_not_includes review_names, 'Electronics'
  end

  test 'approved scope excludes interests needing review' do
    Interest.create!(name: 'Flagged', needs_review: true)
    approved_names = Interest.approved.pluck(:name)
    assert_not_includes approved_names, 'Flagged'
    assert_includes approved_names, 'Electronics'
  end

  test 'suggested includes needs_review interests immediately' do
    pending_interest = Interest.create!(name: 'Pending Interest', needs_review: true)
    result = Interest.suggested(limit: 100)
    assert_includes result.map(&:id), pending_interest.id
  end

  # Associations

  test 'member_count returns number of users with this interest' do
    assert_equal 2, interests(:electronics).member_count
    assert_equal 1, interests(:programming).member_count
    assert_equal 0, interests(:laser_cutting).member_count
  end

  test 'destroying an interest removes associated user_interests' do
    interest  = interests(:programming)
    user      = users(:one)

    assert user.interests.include?(interest)
    interest.destroy!
    assert_not user.reload.interests.include?(interest)
  end

  private

  def interest_errors(interest, field)
    interest.errors[field]
  end
end
