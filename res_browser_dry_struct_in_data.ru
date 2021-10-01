require "bundler/inline"

gemfile do
  source "https://rubygems.org"
  gem "rails_event_store", "2.3.0"
  gem "rails",             "6.1.4.1"
  gem "sqlite3",           "1.4.2"
  gem "dry-struct"
end

require "dry-types"
require "dry-struct"
require "rails_event_store"
require "ruby_event_store/browser/app"


module Types
  include Dry.Types()
  RequiredInspections = Types::Nominal::Hash
end

# https://github.com/RailsEventStore/ecommerce/blob/ddb9ef939a877289b31b19b4c085f298139a0b02/infra/lib/infra/event.rb
class Event < RailsEventStore::Event
  class Schema < Dry::Struct
    transform_keys(&:to_sym)
  end

  class << self
    extend Forwardable
    def_delegators :schema, :attribute, :attribute?

    def schema
      @schema ||= Class.new(Schema)
    end
  end

  def initialize(event_id: SecureRandom.uuid, metadata: nil, data: {})
    super(event_id: event_id, metadata: metadata, data: data.deep_merge(self.class.schema.new(data).to_h))
  end
end

class PolicyBound < Event
  attribute :key1 do
    attribute? :required_inspections, Types::RequiredInspections.default({ types: [], self_inspection: false })
  end
end

setup_event_store = lambda do
  ActiveRecord::Base.establish_connection("sqlite3::memory:")
  ActiveRecord::Schema.define do
    create_table(:event_store_events_in_streams, force: false) do |t|
      t.string      :stream,      null: false
      t.integer     :position,    null: true
      t.references  :event,       null: false, type: :string, limit: 36
      t.datetime    :created_at,  null: false, precision: 6
    end
    add_index :event_store_events_in_streams, [:stream, :position], unique: true
    add_index :event_store_events_in_streams, [:created_at]
    add_index :event_store_events_in_streams, [:stream, :event_id], unique: true

    create_table(:event_store_events, force: false) do |t|
      t.references  :event,       null: false, type: :string, limit: 36
      t.string      :event_type,  null: false
      t.binary      :metadata
      t.binary      :data,        null: false
      t.datetime    :created_at,  null: false, precision: 6
      t.datetime    :valid_at,    null: true,  precision: 6
    end
    # add_index :event_store_events, :event_id, unique: true
    add_index :event_store_events, :created_at
    add_index :event_store_events, :valid_at
    add_index :event_store_events, :event_type
  end

  policy_bound =
    PolicyBound.new(
      event_id: "d2acf188-be88-44ee-b10d-22a33b1999d7",
      data: {
        key1: {
          required_inspections: Types::RequiredInspections[types: ["foo"]]
        }
      }
    )
  event_store =
    RailsEventStore::Client.new
  event_store.publish(policy_bound)

  published_event =
    event_store.read.last
  raise unless policy_bound == published_event

  p policy_bound

  event_store
end

run RubyEventStore::Browser::App.for(event_store_locator: setup_event_store)

