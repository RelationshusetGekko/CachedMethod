module CachedMethod #:nodoc:

  class Item < ActiveRecord::Base #:nodoc:
    set_table_name "cached_method_items"
    serialize :value
  end


  def self.included(base)
    base.extend ClassMethods
  end

  module ClassMethods
  
    # Caches the result of an instance method. Should be called like:
    #
    #   cache_method :some_method,
    #                :expire_after => 1.hour,
    #                :update_after => 10.minutes
    def cache_method(method, *cache_args)
      opts = cache_args.extract_options!
      define_method "#{method}_with_cached_method" do |*args|
        CachedMethod::Cache.get(logger, opts.merge(:method => method, :args => args, :id => id, :klass => self.class)) do
          self.send("#{method}_without_cached_method", *args)
        end
      end
      alias_method_chain method, :cached_method
    end

  end
  
  module Cache #:nodoc:
      
    class << self
      
      def get(logger, opts, &blk)
        entry = CachedMethod::Item.find_by_key(key_for(opts))
        if entry.nil?
          logger.debug("No cache found for #{opts.inspect}")
          create_entry(opts, &blk)
        else
          if expired?(entry, opts)
            logger.debug("Cache expired for #{opts.inspect}")
            update_entry(entry, opts, &blk)
          else
            entry.value
          end
        end
      end
      
      private
      
      def create_entry(opts, &blk)
        value = yield(opts[:args])
        CachedMethod::Item.create(:key => key_for(opts), :value => value, :expires_at => Time.now + opts[:expire_after])
        value
      end

      def update_entry(entry, opts, &blk)
        CachedMethod::Item.transaction do
          entry.update_attributes(:expires_at => Time.now + opts[:expire_after])
          value = yield(opts[:args])
          entry.update_attributes(:value => value)
          value
        end
      end

      def expired?(entry, opts)
        !opts[:expire_after].blank? && 
          entry.updated_at < Time.now - opts[:expire_after]
      end

      def key_for(opts)
        dumped_args = Marshal.dump(opts[:args])
        keystring = opts[:klass].to_s+opts[:method].to_s+opts[:id].to_s+dumped_args.to_s
        Digest::SHA1.hexdigest(keystring)
      end

    end

  end
  
end