# frozen_string_literal: true

require 'test_helper'

module MembershipApplications
  class CsvImporterTest < ActiveSupport::TestCase
    setup do
      @page = ApplicationFormPage.create!(title: 'Importer Test Page', position: 900)
      @page.questions.create!(label: 'Name', field_type: 'text', required: false, position: 1)
      @page.questions.create!(label: 'Mailing Address', field_type: 'text', required: false, position: 2)
    end

    test 'creates application with answers and approved status without journal or queued mail' do
      csv = <<~CSV
        Approved,Timestamp,Email Address,Name,Mailing Address
        Yes,2024-01-15 10:00:00 UTC,importer-test@example.com,Jane Doe,123 Main St
      CSV

      importer = CsvImporter.new(imported_by: users(:one))
      journal_app_actions = %w[application_submitted application_approved application_rejected]
      assert_no_difference -> { Journal.where(action: journal_app_actions).count } do
        assert_no_difference 'QueuedMail.count' do
          result = importer.call(StringIO.new(csv))
          assert_equal 1, result[:imported]
          assert_equal 0, result[:skipped]
          assert_empty result[:errors]
        end
      end

      app = MembershipApplication.find_by!(email: 'importer-test@example.com')
      assert_equal 'approved', app.status
      name_ans = app.application_answers
                    .joins(:application_form_question)
                    .find_by(application_form_questions: { label: 'Name' })
      assert_equal 'Jane Doe', name_ans.value
      addr_ans = app.application_answers
                    .joins(:application_form_question)
                    .find_by(application_form_questions: { label: 'Mailing Address' })
      assert_equal '123 Main St', addr_ans.value
      assert_equal users(:one), app.reviewed_by
      assert app.reviewed_at.present?
    end

    test 'stores unknown columns in admin_notes' do
      csv = <<~CSV
        Approved,Timestamp,Email Address,Name,Estimated co-working hours per week? (@ ^H)
        ,2024-02-01 12:00:00 UTC,extras@example.com,Pat,10
      CSV

      result = CsvImporter.new.call(StringIO.new(csv))
      assert_equal 1, result[:imported]
      app = MembershipApplication.find_by!(email: 'extras@example.com')
      assert_includes app.admin_notes, 'Estimated co-working hours per week? (@ ^H)'
      assert_includes app.admin_notes, '10'
    end

    test 'rejected when Approved is no' do
      csv = <<~CSV
        Approved,Timestamp,Email Address,Name
        No,2024-03-01,rejected@example.com,X
      CSV

      CsvImporter.new(imported_by: users(:one)).call(StringIO.new(csv))
      app = MembershipApplication.find_by!(email: 'rejected@example.com')
      assert_equal 'rejected', app.status
    end

    test 'skipped row with blank email' do
      csv = <<~CSV
        Approved,Timestamp,Email Address,Name
        Yes,2024-01-01,,Nobody
      CSV

      result = CsvImporter.new.call(StringIO.new(csv))
      assert_equal 0, result[:imported]
      assert_equal 1, result[:skipped]
      assert_match(/missing Email Address/, result[:errors].join)
    end
  end
end
