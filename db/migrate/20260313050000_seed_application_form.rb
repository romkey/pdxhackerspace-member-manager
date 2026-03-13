class SeedApplicationForm < ActiveRecord::Migration[8.1]
  def up
    # Intro text fragment
    TextFragment.ensure_exists!(
      key: 'application_form_intro',
      title: 'Application Form Introduction',
      content: <<~HTML
        <h2 class="h4 mb-3">PDX Hackerspace Membership Application</h2>
        <p>
          PDX Hackerspace is a 501(c)(3) non-profit organization promoting and encouraging
          technical, scientific, and artistic skills through individual projects, social
          collaboration, and education. We are located at 7608 N Interstate Avenue in Portland,
          Oregon, and serve as a local community hub as well as a thriving online community
          with roots extending around the world.
        </p>
        <p>Please provide your email address to begin or resume your application.</p>
      HTML
    )

    # Page 1: Contact Information
    p1 = ApplicationFormPage.create!(title: 'Contact Information', position: 1)
    p1.questions.create!(label: 'Name', field_type: 'text', required: true, position: 1)
    p1.questions.create!(label: 'Mailing Address', field_type: 'text', required: true, position: 2)
    p1.questions.create!(label: 'Phone number', field_type: 'text', required: false, position: 3)
    p1.questions.create!(label: 'Other Contact Information (github, socials, etc.)', field_type: 'text', required: false, position: 4)

    # Page 2: Hackerspace Member Referral
    p2 = ApplicationFormPage.create!(
      title: 'Hackerspace Member Referral',
      description: 'If you have been referred by a current member, please provide their information. All fields on this page are optional.',
      position: 2
    )
    p2.questions.create!(label: 'Member Name', field_type: 'text', required: false, position: 1)
    p2.questions.create!(label: 'Member Email', field_type: 'text', required: false, position: 2)
    p2.questions.create!(label: 'Member Phone', field_type: 'text', required: false, position: 3)
    p2.questions.create!(label: 'Other Member Contact Information (socials, etc.)', field_type: 'text', required: false, position: 4)

    # Page 3: General Questions
    p3 = ApplicationFormPage.create!(
      title: 'General Questions',
      description: 'Please answer the following questions to help us get to know you better.',
      position: 3
    )
    p3.questions.create!(
      label: 'Have you ever been a member of a Hackerspace? If yes, please provide details.',
      field_type: 'textarea', required: false, position: 1
    )
    p3.questions.create!(
      label: 'How did you discover PDX Hackerspace?',
      field_type: 'text', required: false, position: 2
    )
    p3.questions.create!(
      label: 'Briefly describe your experience and/or interests with technology, as well as the skills you would bring to the Hackerspace.',
      field_type: 'textarea', required: false, position: 3
    )
    p3.questions.create!(
      label: 'Why do you want to become a member? What new skills would you like to learn?',
      field_type: 'textarea', required: false, position: 4
    )
    p3.questions.create!(
      label: 'Can you commit to volunteering at least 5% of your time spent at the space for Hackerspace responsibilities (e.g., teaching or assisting a class, sharing a skill, cleaning, maintenance)?',
      field_type: 'radio', required: false, position: 5,
      options_json: %w[Yes No Maybe Other].to_json
    )
    p3.questions.create!(
      label: 'Are you planning to use the Hackerspace for co-working?',
      field_type: 'radio', required: true, position: 6,
      options_json: %w[Yes No Maybe Other].to_json
    )

    # Page 4: General Questions, Continued
    p4 = ApplicationFormPage.create!(
      title: 'General Questions, Continued',
      description: 'Please answer the remaining questions to help us get to know you better.',
      position: 4
    )
    p4.questions.create!(
      label: 'How do you make your opinions and concerns known in a group setting? Have you encountered any conflicts in group settings? If so, what were the issues and how were they resolved?',
      field_type: 'textarea', required: false, position: 1
    )
    p4.questions.create!(
      label: 'Describe your experience working in diverse groups or with individuals from different backgrounds. How have you contributed to creating a positive, inclusive, and supportive environment in previous group settings?',
      field_type: 'textarea', required: false, position: 2
    )
    p4.questions.create!(
      label: 'We expect our members to be observant of health and safety protocols, such as wearing masks and maintaining physical distance when required. How would you ensure you are following these protocols and respecting other members\' personal space?',
      field_type: 'textarea', required: false, position: 3
    )

    # Page 5: Feedback
    p5 = ApplicationFormPage.create!(
      title: 'Feedback',
      description: 'Please give any feedback you\'d like below.',
      position: 5
    )
    p5.questions.create!(label: 'Feedback!', field_type: 'textarea', required: false, position: 1)
  end

  def down
    ApplicationFormPage.destroy_all
    TextFragment.find_by(key: 'application_form_intro')&.destroy
  end
end
