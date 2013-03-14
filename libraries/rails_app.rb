class Chef
  module RailsApp
    def run_callback opts = {}
      defaults = {:force => false, :variables => {}}

      # set the options hash
      if opts.is_a? String
        defaults[:file] = opts
        opts = defaults
      else
        opts = defaults.merge(opts)  
      end

      if not opts[:force] and File.exists?(opts[:file])
        variables = opts[:variables] # is available in the callbacks
        eval File.open(opts[:file]).read
      end
    end
  end
end
