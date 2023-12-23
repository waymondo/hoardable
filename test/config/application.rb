# frozen_string_literal: true

class Dummy < Rails::Application
  config.load_defaults Rails::VERSION::STRING.to_f
  config.eager_load = false
  config.active_storage.service_configurations = {}
  config.paths['config/database'] = ['test/config/database.yml']
  config.paths['db/migrate'] = ['tmp/db/migrate']
  config.active_record.encryption&.key_derivation_salt = SecureRandom.hex
  config.active_record.encryption&.primary_key = SecureRandom.hex
  config.active_record.yaml_column_permitted_classes = [ActiveSupport::HashWithIndifferentAccess]
end
