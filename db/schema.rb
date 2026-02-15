# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_02_15_200000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "access_controller_logs", force: :cascade do |t|
    t.bigint "access_controller_id", null: false
    t.string "action", null: false
    t.string "command_line"
    t.datetime "created_at", null: false
    t.integer "exit_code"
    t.text "output"
    t.string "status", default: "running", null: false
    t.datetime "updated_at", null: false
    t.index ["access_controller_id"], name: "index_access_controller_logs_on_access_controller_id"
    t.index ["action"], name: "index_access_controller_logs_on_action"
    t.index ["created_at"], name: "index_access_controller_logs_on_created_at"
    t.index ["status"], name: "index_access_controller_logs_on_status"
  end

  create_table "access_controller_type_training_topics", force: :cascade do |t|
    t.bigint "access_controller_type_id", null: false
    t.datetime "created_at", null: false
    t.bigint "training_topic_id", null: false
    t.datetime "updated_at", null: false
    t.index ["access_controller_type_id", "training_topic_id"], name: "idx_act_training_topics_unique", unique: true
    t.index ["access_controller_type_id"], name: "idx_act_training_topics_on_act_id"
    t.index ["training_topic_id"], name: "idx_act_training_topics_on_topic_id"
  end

  create_table "access_controller_types", force: :cascade do |t|
    t.jsonb "actions", default: [], null: false
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.string "name", null: false
    t.string "script_path", null: false
    t.datetime "updated_at", null: false
    t.index ["enabled"], name: "index_access_controller_types_on_enabled"
    t.index ["name"], name: "index_access_controller_types_on_name", unique: true
  end

  create_table "access_controllers", force: :cascade do |t|
    t.bigint "access_controller_type_id"
    t.string "access_token"
    t.string "backup_status", default: "unknown"
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "display_order", default: 0
    t.boolean "enabled", default: true, null: false
    t.text "environment_variables"
    t.string "hostname", null: false
    t.datetime "last_backup_at"
    t.datetime "last_ping_at"
    t.datetime "last_sync_at"
    t.string "name", null: false
    t.string "nickname"
    t.string "ping_status", default: "unknown"
    t.string "script_arguments"
    t.string "sync_status", default: "unknown", null: false
    t.datetime "updated_at", null: false
    t.index ["access_controller_type_id"], name: "index_access_controllers_on_access_controller_type_id"
    t.index ["enabled"], name: "index_access_controllers_on_enabled"
    t.index ["hostname"], name: "index_access_controllers_on_hostname"
    t.index ["name"], name: "index_access_controllers_on_name", unique: true
  end

  create_table "access_logs", force: :cascade do |t|
    t.string "action"
    t.datetime "created_at", null: false
    t.string "location"
    t.datetime "logged_at"
    t.string "name"
    t.text "raw_text"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["location"], name: "index_access_logs_on_location"
    t.index ["logged_at"], name: "index_access_logs_on_logged_at"
    t.index ["name"], name: "index_access_logs_on_name"
    t.index ["user_id"], name: "index_access_logs_on_user_id"
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "application_groups", force: :cascade do |t|
    t.bigint "application_id", null: false
    t.string "authentik_group_id"
    t.string "authentik_name"
    t.datetime "created_at", null: false
    t.string "name"
    t.text "note"
    t.bigint "training_topic_id"
    t.datetime "updated_at", null: false
    t.boolean "use_can_train", default: false, null: false
    t.boolean "use_default_admins_group", default: false, null: false
    t.boolean "use_default_members_group", default: false, null: false
    t.boolean "use_trained_in", default: false, null: false
    t.index ["application_id"], name: "index_application_groups_on_application_id"
    t.index ["authentik_group_id"], name: "index_application_groups_on_authentik_group_id"
    t.index ["training_topic_id"], name: "index_application_groups_on_training_topic_id"
  end

  create_table "application_groups_users", id: false, force: :cascade do |t|
    t.bigint "application_group_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["application_group_id", "user_id"], name: "index_app_groups_users_on_group_and_user", unique: true
    t.index ["application_group_id"], name: "index_application_groups_users_on_application_group_id"
    t.index ["user_id"], name: "index_application_groups_users_on_user_id"
  end

  create_table "applications", force: :cascade do |t|
    t.string "authentik_prefix"
    t.datetime "created_at", null: false
    t.string "external_url"
    t.string "internal_url"
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "authentik_users", force: :cascade do |t|
    t.string "authentik_id", null: false
    t.datetime "created_at", null: false
    t.string "email"
    t.string "full_name"
    t.boolean "is_active", default: true, null: false
    t.boolean "is_superuser", default: false, null: false
    t.datetime "last_synced_at"
    t.jsonb "raw_attributes", default: {}, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.string "username"
    t.index ["authentik_id"], name: "index_authentik_users_on_authentik_id", unique: true
    t.index ["email"], name: "index_authentik_users_on_email"
    t.index ["raw_attributes"], name: "index_authentik_users_on_raw_attributes", using: :gin
    t.index ["user_id"], name: "index_authentik_users_on_user_id"
  end

  create_table "default_settings", force: :cascade do |t|
    t.string "active_members_group", null: false
    t.string "admins_group", null: false
    t.string "app_prefix", null: false
    t.string "can_train_prefix", null: false
    t.datetime "created_at", null: false
    t.string "members_prefix", null: false
    t.string "site_prefix", default: "ctrlh", null: false
    t.boolean "sync_inactive_members", default: false, null: false
    t.string "trained_on_prefix", null: false
    t.datetime "updated_at", null: false
  end

  create_table "document_training_topics", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "document_id", null: false
    t.bigint "training_topic_id", null: false
    t.datetime "updated_at", null: false
    t.index ["document_id"], name: "index_document_training_topics_on_document_id"
    t.index ["training_topic_id"], name: "index_document_training_topics_on_training_topic_id"
  end

  create_table "documents", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "show_on_all_profiles", default: false, null: false
    t.string "title"
    t.datetime "updated_at", null: false
  end

  create_table "email_templates", force: :cascade do |t|
    t.text "body_html", null: false
    t.text "body_text", null: false
    t.datetime "created_at", null: false
    t.string "description"
    t.boolean "enabled", default: true, null: false
    t.string "key", null: false
    t.string "name", null: false
    t.string "subject", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_email_templates_on_key", unique: true
  end

  create_table "incident_report_links", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "incident_report_id", null: false
    t.integer "position", default: 0
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.index ["incident_report_id", "position"], name: "index_incident_report_links_on_incident_report_id_and_position"
    t.index ["incident_report_id"], name: "index_incident_report_links_on_incident_report_id"
  end

  create_table "incident_report_members", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "incident_report_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["incident_report_id", "user_id"], name: "idx_incident_report_members_unique", unique: true
    t.index ["incident_report_id"], name: "index_incident_report_members_on_incident_report_id"
    t.index ["user_id"], name: "index_incident_report_members_on_user_id"
  end

  create_table "incident_reports", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.date "incident_date", null: false
    t.string "incident_type", null: false
    t.string "other_type_explanation"
    t.bigint "reporter_id", null: false
    t.text "resolution"
    t.string "status", default: "draft", null: false
    t.string "subject", null: false
    t.datetime "updated_at", null: false
    t.index ["incident_date"], name: "index_incident_reports_on_incident_date"
    t.index ["incident_type"], name: "index_incident_reports_on_incident_type"
    t.index ["reporter_id"], name: "index_incident_reports_on_reporter_id"
    t.index ["status"], name: "index_incident_reports_on_status"
  end

  create_table "incoming_webhooks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "enabled", default: true, null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.string "webhook_type", null: false
    t.index ["slug"], name: "index_incoming_webhooks_on_slug", unique: true
    t.index ["webhook_type"], name: "index_incoming_webhooks_on_webhook_type", unique: true
  end

  create_table "journals", force: :cascade do |t|
    t.string "action", null: false
    t.bigint "actor_user_id"
    t.datetime "changed_at", null: false
    t.jsonb "changes_json", default: {}, null: false
    t.datetime "created_at", null: false
    t.boolean "highlight", default: false, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["actor_user_id"], name: "index_journals_on_actor_user_id"
    t.index ["changed_at"], name: "index_journals_on_changed_at"
    t.index ["highlight"], name: "index_journals_on_highlight"
    t.index ["user_id"], name: "index_journals_on_user_id"
  end

  create_table "kofi_payments", force: :cascade do |t|
    t.decimal "amount", precision: 12, scale: 2
    t.datetime "created_at", null: false
    t.string "currency"
    t.string "email"
    t.string "from_name"
    t.boolean "is_first_subscription_payment", default: false
    t.boolean "is_public", default: false
    t.boolean "is_subscription_payment", default: false
    t.string "kofi_transaction_id", null: false
    t.datetime "last_synced_at"
    t.text "message"
    t.string "message_id"
    t.string "payment_type"
    t.jsonb "raw_attributes", default: {}, null: false
    t.bigint "sheet_entry_id"
    t.jsonb "shop_items", default: []
    t.string "status"
    t.string "tier_name"
    t.datetime "timestamp"
    t.datetime "updated_at", null: false
    t.string "url"
    t.bigint "user_id"
    t.index ["email"], name: "index_kofi_payments_on_email"
    t.index ["kofi_transaction_id"], name: "index_kofi_payments_on_kofi_transaction_id", unique: true
    t.index ["message_id"], name: "index_kofi_payments_on_message_id"
    t.index ["sheet_entry_id"], name: "index_kofi_payments_on_sheet_entry_id"
    t.index ["user_id"], name: "index_kofi_payments_on_user_id"
  end

  create_table "local_accounts", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.boolean "admin", default: false, null: false
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "full_name"
    t.datetime "last_signed_in_at"
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_local_accounts_on_email", unique: true
  end

  create_table "member_sources", force: :cascade do |t|
    t.boolean "api_configured", default: false
    t.datetime "created_at", null: false
    t.integer "display_order", default: 0
    t.boolean "enabled", default: true, null: false
    t.integer "entry_count", default: 0
    t.string "key", null: false
    t.datetime "last_sync_at"
    t.integer "linked_count", default: 0
    t.string "name", null: false
    t.text "notes"
    t.integer "unlinked_count", default: 0
    t.datetime "updated_at", null: false
    t.index ["display_order"], name: "index_member_sources_on_display_order"
    t.index ["enabled"], name: "index_member_sources_on_enabled"
    t.index ["key"], name: "index_member_sources_on_key", unique: true
  end

  create_table "membership_plans", force: :cascade do |t|
    t.string "billing_frequency", null: false
    t.decimal "cost", precision: 10, scale: 2, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "manual", default: false, null: false
    t.string "name", null: false
    t.string "payment_link"
    t.string "paypal_transaction_subject"
    t.string "plan_type", default: "primary", null: false
    t.datetime "updated_at", null: false
    t.boolean "visible", default: true, null: false
    t.index ["manual"], name: "index_membership_plans_on_manual"
    t.index ["name"], name: "index_membership_plans_on_name", unique: true
    t.index ["plan_type"], name: "index_membership_plans_on_plan_type"
    t.index ["visible"], name: "index_membership_plans_on_visible"
  end

  create_table "membership_settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "payment_grace_period_days", default: 14, null: false
    t.integer "reactivation_grace_period_months", default: 3, null: false
    t.datetime "updated_at", null: false
  end

  create_table "payment_processors", force: :cascade do |t|
    t.decimal "amount_last_30_days", precision: 12, scale: 2, default: "0.0"
    t.boolean "api_configured", default: false
    t.decimal "average_payment_amount", precision: 12, scale: 2, default: "0.0"
    t.integer "consecutive_error_count", default: 0
    t.datetime "created_at", null: false
    t.integer "csv_import_count", default: 0
    t.integer "display_order", default: 0
    t.boolean "enabled", default: true, null: false
    t.string "key", null: false
    t.datetime "last_csv_import_at"
    t.string "last_error_message"
    t.datetime "last_successful_sync_at"
    t.datetime "last_sync_at"
    t.integer "matched_payments_count", default: 0
    t.string "name", null: false
    t.text "notes"
    t.string "payment_link"
    t.string "sync_status", default: "unknown"
    t.decimal "total_amount", precision: 12, scale: 2, default: "0.0"
    t.integer "total_payments_count", default: 0
    t.integer "unmatched_payments_count", default: 0
    t.datetime "updated_at", null: false
    t.boolean "webhook_configured", default: false
    t.datetime "webhook_last_received_at"
    t.string "webhook_url"
    t.index ["display_order"], name: "index_payment_processors_on_display_order"
    t.index ["enabled"], name: "index_payment_processors_on_enabled"
    t.index ["key"], name: "index_payment_processors_on_key", unique: true
  end

  create_table "paypal_payments", force: :cascade do |t|
    t.decimal "amount", precision: 12, scale: 2
    t.datetime "created_at", null: false
    t.string "currency"
    t.boolean "dont_link", default: false, null: false
    t.datetime "last_synced_at"
    t.boolean "matches_plan", default: true, null: false
    t.string "payer_email"
    t.string "payer_id"
    t.string "payer_name"
    t.string "paypal_id", null: false
    t.jsonb "raw_attributes", default: {}, null: false
    t.string "status"
    t.datetime "transaction_time"
    t.string "transaction_type"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["matches_plan"], name: "index_paypal_payments_on_matches_plan"
    t.index ["payer_email"], name: "index_paypal_payments_on_payer_email"
    t.index ["paypal_id"], name: "index_paypal_payments_on_paypal_id", unique: true
    t.index ["user_id"], name: "index_paypal_payments_on_user_id"
  end

  create_table "recharge_payments", force: :cascade do |t|
    t.decimal "amount", precision: 12, scale: 2
    t.string "charge_type"
    t.datetime "created_at", null: false
    t.string "currency"
    t.string "customer_email"
    t.string "customer_id"
    t.string "customer_name"
    t.boolean "dont_link", default: false, null: false
    t.datetime "last_synced_at"
    t.datetime "processed_at"
    t.jsonb "raw_attributes", default: {}, null: false
    t.string "recharge_id", null: false
    t.string "status"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["customer_email"], name: "index_recharge_payments_on_customer_email"
    t.index ["customer_id"], name: "index_recharge_payments_on_customer_id"
    t.index ["processed_at"], name: "index_recharge_payments_on_processed_at", order: :desc
    t.index ["recharge_id"], name: "index_recharge_payments_on_recharge_id", unique: true
    t.index ["user_id"], name: "index_recharge_payments_on_user_id"
  end

  create_table "rfid_readers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", limit: 32, null: false
    t.string "name", null: false
    t.text "note"
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_rfid_readers_on_key", unique: true
  end

  create_table "rfids", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "notes"
    t.string "rfid", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["rfid"], name: "index_rfids_on_rfid"
    t.index ["user_id"], name: "index_rfids_on_user_id"
  end

  create_table "sheet_entries", force: :cascade do |t|
    t.string "alias_name"
    t.datetime "created_at", null: false
    t.datetime "date_added"
    t.string "dirty"
    t.string "dremel"
    t.string "email"
    t.string "embroidery_machine"
    t.string "ender"
    t.string "event_host"
    t.string "general_shop"
    t.string "laminator"
    t.string "laser"
    t.datetime "last_synced_at"
    t.string "longmill"
    t.string "mpcnc_marlin"
    t.string "name", null: false
    t.text "notes"
    t.string "payment"
    t.string "paypal_name"
    t.string "prusa"
    t.jsonb "raw_attributes", default: {}, null: false
    t.string "rfid"
    t.string "serger"
    t.string "sewing_machine"
    t.string "shaper"
    t.string "status"
    t.string "twitter"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.string "vinyl_cutter"
    t.index ["email"], name: "index_sheet_entries_on_email"
    t.index ["name"], name: "index_sheet_entries_on_name"
    t.index ["user_id"], name: "index_sheet_entries_on_user_id"
  end

  create_table "slack_users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "deleted", default: false, null: false
    t.string "display_name"
    t.boolean "dont_link", default: false, null: false
    t.string "email"
    t.boolean "is_admin", default: false, null: false
    t.boolean "is_bot", default: false, null: false
    t.boolean "is_owner", default: false, null: false
    t.datetime "last_active_at"
    t.datetime "last_synced_at"
    t.string "phone"
    t.string "pronouns"
    t.jsonb "raw_attributes", default: {}, null: false
    t.string "real_name"
    t.string "slack_id", null: false
    t.boolean "slack_status", default: false, null: false
    t.string "team_id"
    t.string "title"
    t.string "tz"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.string "username"
    t.index ["email"], name: "index_slack_users_on_email", unique: true, where: "(email IS NOT NULL)"
    t.index ["raw_attributes"], name: "index_slack_users_on_raw_attributes", using: :gin
    t.index ["slack_id"], name: "index_slack_users_on_slack_id", unique: true
    t.index ["user_id"], name: "index_slack_users_on_user_id"
  end

  create_table "text_fragments", force: :cascade do |t|
    t.text "content"
    t.datetime "created_at", null: false
    t.string "key"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_text_fragments_on_key", unique: true
  end

  create_table "trainer_capabilities", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "training_topic_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["training_topic_id"], name: "index_trainer_capabilities_on_training_topic_id"
    t.index ["user_id", "training_topic_id"], name: "index_trainer_capabilities_on_user_id_and_training_topic_id", unique: true
    t.index ["user_id"], name: "index_trainer_capabilities_on_user_id"
  end

  create_table "training_topic_links", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "title", null: false
    t.bigint "training_topic_id", null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.index ["training_topic_id"], name: "index_training_topic_links_on_training_topic_id"
  end

  create_table "training_topics", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_training_topics_on_name", unique: true
  end

  create_table "trainings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "notes"
    t.datetime "trained_at", null: false
    t.bigint "trainee_id", null: false
    t.bigint "trainer_id"
    t.bigint "training_topic_id", null: false
    t.datetime "updated_at", null: false
    t.index ["trained_at"], name: "index_trainings_on_trained_at"
    t.index ["trainee_id"], name: "index_trainings_on_trainee_id"
    t.index ["trainer_id"], name: "index_trainings_on_trainer_id"
    t.index ["training_topic_id"], name: "index_trainings_on_training_topic_id"
  end

  create_table "user_links", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "position", default: 0
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "position"], name: "index_user_links_on_user_id_and_position"
    t.index ["user_id"], name: "index_user_links_on_user_id"
  end

  create_table "user_supplementary_plans", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "membership_plan_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["membership_plan_id"], name: "index_user_supplementary_plans_on_membership_plan_id"
    t.index ["user_id", "membership_plan_id"], name: "index_user_supplementary_plans_unique", unique: true
    t.index ["user_id"], name: "index_user_supplementary_plans_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "active", default: false, null: false
    t.string "aliases", default: [], null: false, array: true
    t.jsonb "authentik_attributes", default: {}, null: false
    t.boolean "authentik_dirty", default: false, null: false
    t.string "authentik_id"
    t.string "avatar"
    t.text "bio"
    t.datetime "created_at", null: false
    t.boolean "do_not_greet", default: false, null: false
    t.string "dues_status", default: "unknown"
    t.string "email"
    t.string "extra_emails", default: [], array: true
    t.string "full_name"
    t.string "greeting_name"
    t.boolean "is_admin", default: false, null: false
    t.datetime "last_login_at"
    t.date "last_payment_date"
    t.datetime "last_synced_at"
    t.date "membership_ended_date"
    t.bigint "membership_plan_id"
    t.date "membership_start_date"
    t.string "membership_status", default: "unknown"
    t.text "notes"
    t.string "payment_type", default: "unknown"
    t.string "paypal_account_id"
    t.string "profile_visibility", default: "members", null: false
    t.string "pronouns"
    t.string "recharge_customer_id"
    t.datetime "recharge_most_recent_payment_date"
    t.boolean "seen_member_help", default: false, null: false
    t.boolean "service_account", default: false, null: false
    t.string "sign_name"
    t.string "slack_handle"
    t.string "slack_id"
    t.datetime "updated_at", null: false
    t.boolean "use_full_name_for_greeting", default: true, null: false
    t.boolean "use_username_for_greeting", default: false, null: false
    t.string "username"
    t.index ["authentik_attributes"], name: "index_users_on_authentik_attributes", using: :gin
    t.index ["authentik_dirty"], name: "index_users_on_authentik_dirty"
    t.index ["authentik_id"], name: "index_users_on_authentik_id", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true, where: "(email IS NOT NULL)"
    t.index ["membership_plan_id"], name: "index_users_on_membership_plan_id"
    t.index ["paypal_account_id"], name: "index_users_on_paypal_account_id"
    t.index ["recharge_customer_id"], name: "index_users_on_recharge_customer_id"
    t.index ["username"], name: "index_users_on_username", unique: true, where: "(username IS NOT NULL)"
  end

  add_foreign_key "access_controller_logs", "access_controllers"
  add_foreign_key "access_controller_type_training_topics", "access_controller_types"
  add_foreign_key "access_controller_type_training_topics", "training_topics"
  add_foreign_key "access_controllers", "access_controller_types"
  add_foreign_key "access_logs", "users"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "application_groups", "applications"
  add_foreign_key "application_groups", "training_topics"
  add_foreign_key "application_groups_users", "application_groups"
  add_foreign_key "application_groups_users", "users"
  add_foreign_key "authentik_users", "users"
  add_foreign_key "document_training_topics", "documents"
  add_foreign_key "document_training_topics", "training_topics"
  add_foreign_key "incident_report_links", "incident_reports"
  add_foreign_key "incident_report_members", "incident_reports"
  add_foreign_key "incident_report_members", "users"
  add_foreign_key "incident_reports", "users", column: "reporter_id"
  add_foreign_key "journals", "users"
  add_foreign_key "journals", "users", column: "actor_user_id"
  add_foreign_key "kofi_payments", "sheet_entries"
  add_foreign_key "kofi_payments", "users"
  add_foreign_key "paypal_payments", "users"
  add_foreign_key "recharge_payments", "users"
  add_foreign_key "rfids", "users"
  add_foreign_key "sheet_entries", "users"
  add_foreign_key "slack_users", "users"
  add_foreign_key "trainer_capabilities", "training_topics"
  add_foreign_key "trainer_capabilities", "users"
  add_foreign_key "training_topic_links", "training_topics"
  add_foreign_key "trainings", "training_topics"
  add_foreign_key "trainings", "users", column: "trainee_id"
  add_foreign_key "trainings", "users", column: "trainer_id"
  add_foreign_key "user_links", "users"
  add_foreign_key "user_supplementary_plans", "membership_plans"
  add_foreign_key "user_supplementary_plans", "users"
  add_foreign_key "users", "membership_plans"
end
