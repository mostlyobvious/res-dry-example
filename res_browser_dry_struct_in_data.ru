require "bundler/inline"

gemfile do
  source "https://rubygems.org"
  gem "ruby_event_store",         "2.3.0"
  gem "ruby_event_store-browser", "2.3.0"
  gem "dry-struct"
  gem "activesupport"
end

require "dry-types"
require "dry-struct"
require "ruby_event_store"
require "ruby_event_store/browser/app"
require "active_support/core_ext/hash/deep_merge"


module Types
  include Dry.Types()
  RequiredInspections = Types::Nominal::Hash
end

# https://github.com/RailsEventStore/ecommerce/blob/ddb9ef939a877289b31b19b4c085f298139a0b02/infra/lib/infra/event.rb
class Event < RubyEventStore::Event
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


module PolicyAdministration
  # Type representing attributes that are stable
  # for the duration of a policy term.
  class InsuranceAttributes < Dry::Struct
    transform_keys(&:to_sym)

    attribute? :required_inspections, Types::RequiredInspections.default({ types: [], self_inspection: false })
  end
end

class PolicyBound < Event
  attribute :key1, PolicyAdministration::InsuranceAttributes
end

setup_event_store = lambda do
  policy_bound =
    PolicyBound.new(
      event_id: "d2acf188-be88-44ee-b10d-22a33b1999d7",
      data: {
        key1: PolicyAdministration::InsuranceAttributes.new
      }
    )
  event_store =
    RubyEventStore::Client.new(
      repository: RubyEventStore::InMemoryRepository.new(serializer: YAML)
    )
  event_store.publish(policy_bound)

  published_event =
    event_store.read.last
  raise unless policy_bound == published_event

  p policy_bound

  event_store
end

run RubyEventStore::Browser::App.for(event_store_locator: setup_event_store)

