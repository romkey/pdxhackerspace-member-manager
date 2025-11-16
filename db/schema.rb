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

ActiveRecord::Schema[7.1].define(version: 2025_11_15_101500) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "journals", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "actor_user_id"
    t.string "action", null: false
    t.jsonb "changes_json", default: {}, null: false
    t.datetime "changed_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_user_id"], name: "index_journals_on_actor_user_id"
    t.index ["changed_at"], name: "index_journals_on_changed_at"
    t.index ["user_id"], name: "index_journals_on_user_id"
  end

  create_table "local_accounts", force: :cascade do |t|
    t.string "email", null: false
    t.string "full_name"
    t.string "password_digest", null: false
    t.boolean "active", default: true, null: false
    t.boolean "admin", default: false, null: false
    t.datetime "last_signed_in_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_local_accounts_on_email", unique: true
  end

  create_table "paypal_payments", force: :cascade do |t|
    t.string "paypal_id", null: false
    t.string "status"
    t.decimal "amount", precision: 12, scale: 2
    t.string "currency"
    t.datetime "transaction_time"
    t.string "transaction_type"
    t.string "payer_email"
    t.string "payer_name"
    t.string "payer_id"
    t.jsonb "raw_attributes", default: {}, null: false
    t.datetime "last_synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.bigint "sheet_entry_id"
    t.index ["payer_email"], name: "index_paypal_payments_on_payer_email"
    t.index ["paypal_id"], name: "index_paypal_payments_on_paypal_id", unique: true
    t.index ["sheet_entry_id"], name: "index_paypal_payments_on_sheet_entry_id"
    t.index ["user_id"], name: "index_paypal_payments_on_user_id"
  end

  create_table "recharge_payments", force: :cascade do |t|
    t.string "recharge_id", null: false
    t.string "status"
    t.decimal "amount", precision: 12, scale: 2
    t.string "currency"
    t.datetime "processed_at"
    t.string "charge_type"
    t.string "customer_email"
    t.string "customer_name"
    t.jsonb "raw_attributes", default: {}, null: false
    t.datetime "last_synced_at"
    t.bigint "user_id"
    t.bigint "sheet_entry_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_email"], name: "index_recharge_payments_on_customer_email"
    t.index ["recharge_id"], name: "index_recharge_payments_on_recharge_id", unique: true
    t.index ["sheet_entry_id"], name: "index_recharge_payments_on_sheet_entry_id"
    t.index ["user_id"], name: "index_recharge_payments_on_user_id"
  end

  create_table "sheet_entries", force: :cascade do |t|
    t.string "name", null: false
    t.string "dirty"
    t.string "status"
    t.string "twitter"
    t.string "alias_name"
    t.string "email"
    t.datetime "date_added"
    t.string "payment"
    t.string "paypal_name"
    t.text "notes"
    t.string "rfid"
    t.string "laser"
    t.string "sewing_machine"
    t.string "serger"
    t.string "embroidery_machine"
    t.string "dremel"
    t.string "ender"
    t.string "prusa"
    t.string "laminator"
    t.string "shaper"
    t.string "general_shop"
    t.string "event_host"
    t.string "vinyl_cutter"
    t.string "mpcnc_marlin"
    t.string "longmill"
    t.jsonb "raw_attributes", default: {}, null: false
    t.datetime "last_synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_sheet_entries_on_email"
    t.index ["name"], name: "index_sheet_entries_on_name"
  end

  create_table "slack_users", force: :cascade do |t|
    t.string "slack_id", null: false
    t.string "team_id"
    t.string "username"
    t.string "real_name"
    t.string "display_name"
    t.string "email"
    t.string "title"
    t.string "phone"
    t.string "tz"
    t.boolean "is_admin", default: false, null: false
    t.boolean "is_owner", default: false, null: false
    t.boolean "is_bot", default: false, null: false
    t.boolean "deleted", default: false, null: false
    t.jsonb "raw_attributes", default: {}, null: false
    t.datetime "last_synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_slack_users_on_email", unique: true, where: "(email IS NOT NULL)"
    t.index ["raw_attributes"], name: "index_slack_users_on_raw_attributes", using: :gin
    t.index ["slack_id"], name: "index_slack_users_on_slack_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "authentik_id", null: false
    t.string "email"
    t.string "full_name"
    t.boolean "active", default: true, null: false
    t.datetime "last_synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "authentik_attributes", default: {}, null: false
    t.index ["authentik_attributes"], name: "index_users_on_authentik_attributes", using: :gin
    t.index ["authentik_id"], name: "index_users_on_authentik_id", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true, where: "(email IS NOT NULL)"
  end

  add_foreign_key "journals", "users"
  add_foreign_key "journals", "users", column: "actor_user_id"
  add_foreign_key "paypal_payments", "sheet_entries"
  add_foreign_key "paypal_payments", "users"
  add_foreign_key "recharge_payments", "sheet_entries"
  add_foreign_key "recharge_payments", "users"
end
