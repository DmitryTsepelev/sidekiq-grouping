module Sidekiq
  module Grouping
    class Middleware
      def call(worker_class, msg, queue, redis_pool = nil)
        return yield if (defined?(Sidekiq::Testing) && Sidekiq::Testing.inline?)

        worker_class = constantize(worker_class.camelize) if worker_class.is_a?(String)
        options = worker_class.get_sidekiq_options

        batch =
          options.key?('batch_flush_size') ||
          options.key?('batch_flush_interval') ||
          options.key?('batch_size')

        passthrough =
          msg['args'] &&
          msg['args'].is_a?(Array) &&
          msg['args'].try(:first) == true

        retrying = msg["failed_at"].present?

        return yield unless batch

        if !(passthrough || retrying)
          add_to_batch(worker_class, queue, msg, redis_pool)
        else
          msg['args'].shift if passthrough
          yield
        end
      end

      private

      def add_to_batch(worker_class, queue, msg, redis_pool = nil)
        Sidekiq::Grouping::Batch
          .new(worker_class.name, queue, redis_pool)
          .add(msg['args'])

        nil
      end

      # https://github.com/mperham/sidekiq/blob/v6.0.7/lib/sidekiq/processor.rb#L267
      def constantize(str)
        return Object.const_get(str) unless str.include?("::")

        names = str.split("::")
        names.shift if names.empty? || names.first.empty?

        names.inject(Object) do |constant, name|
          # the false flag limits search for name to under the constant namespace
          #   which mimics Rails' behaviour
          constant.const_get(name, false)
        end
      end
    end
  end
end
