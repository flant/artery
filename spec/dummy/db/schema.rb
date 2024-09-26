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

ActiveRecord::Schema[7.2].define(version: 2024_04_11_120304) do
  create_table "artery_messages", force: :cascade do |t|
    t.string "version"
    t.string "model", null: false
    t.string "action", null: false
    t.text "data", null: false
    t.datetime "created_at"
    t.index ["model"], name: "index_artery_messages_on_model"
  end

  create_table "artery_subscription_infos", force: :cascade do |t|
    t.string "service", null: false
    t.string "model", null: false
    t.boolean "synchronization_in_progress", default: false
    t.integer "synchronization_page"
    t.string "subscriber"
    t.integer "latest_index"
    t.datetime "synchronization_heartbeat"
  end
end
