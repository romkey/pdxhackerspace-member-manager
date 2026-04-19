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

    test 'parses US-style timestamp in Timestamp column' do
      csv = <<~CSV
        Approved,Timestamp,Email Address,Name
        Yes,5/4/2023 16:13:19,us-date@example.com,Pat
      CSV

      CsvImporter.new.call(StringIO.new(csv))
      app = MembershipApplication.find_by!(email: 'us-date@example.com')
      assert_equal Time.zone.local(2023, 5, 4, 16, 13, 19), app.submitted_at
    end

    test 'merge fills submitted_at when missing and does not create duplicate application' do
      existing = MembershipApplication.create!(
        email: 'merge-submitted@example.com',
        status: 'submitted',
        submitted_at: nil
      )
      csv = <<~CSV
        Approved,Timestamp,Email Address,Name
        ,5/4/2023 16:13:19,merge-submitted@example.com,Pat
      CSV

      assert_no_difference 'MembershipApplication.count' do
        result = CsvImporter.new.call(StringIO.new(csv))
        assert_equal 1, result[:imported]
      end

      assert_equal Time.zone.local(2023, 5, 4, 16, 13, 19), existing.reload.submitted_at
    end

    test 'merge leaves submitted_at unchanged when already set' do
      t = Time.zone.parse('2022-06-01 12:00:00')
      existing = MembershipApplication.create!(
        email: 'merge-keep-ts@example.com',
        status: 'submitted',
        submitted_at: t
      )
      csv = <<~CSV
        Approved,Timestamp,Email Address,Name
        ,5/4/2023 16:13:19,merge-keep-ts@example.com,Pat
      CSV

      CsvImporter.new.call(StringIO.new(csv))
      assert_equal t, existing.reload.submitted_at
    end

    test 'merge updates answers without duplicate answer rows' do
      existing = MembershipApplication.create!(
        email: 'merge-answers@example.com',
        status: 'submitted',
        submitted_at: Time.current
      )
      existing.application_answers.create!(
        application_form_question: @page.questions.find_by!(label: 'Name'),
        value: 'Old'
      )

      csv = <<~CSV
        Approved,Timestamp,Email Address,Name
        ,2024-01-01,merge-answers@example.com,New Name
      CSV

      assert_no_difference -> { ApplicationAnswer.count } do
        CsvImporter.new.call(StringIO.new(csv))
      end

      assert_equal 'New Name', existing.reload.application_answers
                                       .joins(:application_form_question)
                                       .find_by(application_form_questions: { label: 'Name' }).value
    end

    test 'Approved starting with n sets rejected and notes after n' do
      csv = <<~CSV
        Approved,Timestamp,Email Address,Name
        nDid not follow up,2024-01-01,n-prefix@example.com,X
      CSV

      CsvImporter.new.call(StringIO.new(csv))
      app = MembershipApplication.find_by!(email: 'n-prefix@example.com')
      assert_equal 'rejected', app.status
      assert_includes app.admin_notes, 'Did not follow up'
    end

    test 'Approved free text not starting with n or y sets submitted and stores column in admin_notes' do
      csv = <<~CSV
        Approved,Timestamp,Email Address,Name
        Deferred — ask next month,2024-01-01,freetext@example.com,X
      CSV

      CsvImporter.new.call(StringIO.new(csv))
      app = MembershipApplication.find_by!(email: 'freetext@example.com')
      assert_equal 'submitted', app.status
      assert_includes app.admin_notes, 'Deferred — ask next month'
    end

    test 'Email Address column is not copied into admin_notes as unmapped' do
      csv = <<~CSV
        Approved,Timestamp,Email Address,Name
        Yes,2024-01-01,email-col-notes@example.com,Sam
      CSV

      CsvImporter.new.call(StringIO.new(csv))
      app = MembershipApplication.find_by!(email: 'email-col-notes@example.com')
      assert_nil app.admin_notes.presence
    end
  end
end
