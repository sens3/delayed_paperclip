module DelayedPaperclip
  
  class <<self
    def included base
      base.extend ClassMethods
    end
  end
  
  class InvalidOptionError < StandardError #:nodoc:
  end
  
  module ClassMethods

    def delay_paperclip(options = {})      
      include InstanceMethods
            
      after_create :save_file_locally
      after_create :enqueue_new_job
      
      define_method :options do
        options
      end
      
      validate_options options
      
      FileUtils.mkdir_p options[:tmp_dir]
      alias_method_chain :save_attached_files, :interrupt
    end
    
    private
    
    def validate_options options
      begin
        self.new.job_class.class
      rescue NameError
        raise InvalidOptionError.new("invalid class name: #{options[:job_class]}")
      end  
    end
        
  end
   
  module InstanceMethods
    
    def save_file_locally
      logger.info "saving file at #{tmp_path}"
      File.open(tmp_path, 'w+') { |f| f.write(self.send(attachment_name).queued_for_write[:original].read) }
    end
    
    def enqueue_new_job
      Delayed::Job.enqueue job_class.new(self.id)
    end
    
    def save_attached_files_with_interrupt
      return if pending?
      save_attached_files_without_interrupt
    end
    
    def attachment_name
      self.class.attachment_definitions.keys.first
    end
    
    def file_name
      self.send("#{attachment_name}_file_name")
    end
    
    def tmp_path
      raise "Cant use tmp_path for unsaved object" if self.new_record?
      File.join(options[:tmp_dir], "#{self.id}-#{file_name}")
    end
    
    def job_class
      eval(options[:job_class].to_s)
    end
    
  end  
  
end

if Object.const_defined?("ActiveRecord")
  ActiveRecord::Base.send(:include, DelayedPaperclip)
end