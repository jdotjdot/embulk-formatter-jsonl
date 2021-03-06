require 'jrjackson'

module Embulk
  module Formatter

    class JsonlFormatterPlugin < FormatterPlugin
      Plugin.register_formatter("jsonl", self)

      VALID_ENCODINGS = %w(UTF-8 UTF-16LE UTF-32BE UTF-32LE UTF-32BE)
      NEWLINES = {
        'CRLF' => "\r\n",
        'LF' => "\n",
        'CR' => "\r",
        # following are not jsonl, but useful in some case
        'NUL' => "\0",
        'NO' => '',

        # Custom additions to enable non-jsonl style formatting
        'COMMA' => ",\n",
      }

      def self.join_texts((*inits,last), opt = {})
        delim = opt[:delimiter] || ', '
        last_delim = opt[:last_delimiter] || ' or '
        [inits.join(delim),last].join(last_delim)
      end

      def self.transaction(config, schema, &control)
        # configuration code:
        task = {
          'encoding' => config.param('encoding', :string, default: 'UTF-8'),
          'newline' => config.param('newline', :string, default: 'LF'),
          'date_format' => config.param('date_format', :string, default: nil),
          'timezone' => config.param('timezone', :string, default: nil ),
          'json_columns' => config.param("json_columns", :array,  default: []),
          'max_file_size' => config.param("max_file_size", :string, default: 32),
          'as_json' => config.param("as_json", :bool, default: false)
        }

        if task['as_json']
          task['newline'] = 'COMMA'
        end

        encoding = task['encoding'].upcase
        raise "encoding must be one of #{join_texts(VALID_ENCODINGS)}" unless VALID_ENCODINGS.include?(encoding)

        newline = task['newline'].upcase
        raise "newline must be one of #{join_texts(NEWLINES.keys)}" unless NEWLINES.has_key?(newline)

        yield(task)
      end

      def init
        # initialization code:
        @encoding = task['encoding'].upcase
        @newline = NEWLINES[task['newline'].upcase]
        @json_columns = task["json_columns"]
        @max_file_size = task["max_file_size"].to_f

        @as_json = task["as_json"]
        @header_print = true

        # your data
        @current_file == nil
        @current_file_size = 0
        @opts = { :mode => :compat }
        date_format = task['date_format']
        timezone = task['timezone']
        @opts[:date_format] = date_format if date_format
        @opts[:timezone] = timezone if timezone
      end

      def close
      end

      def add(page)
        # output code:
        page.each do |record|

          if @current_file == nil || @current_file_size > (@max_file_size * 1024 * 1024)
            if @as_json and @current_file != nil
              # if we're at the end of an existing file, print the footer
              @current_file.write ']'.encode(@encoding)
            end

            @current_file = file_output.next_file
            @current_file_size = 0
            @header_print = true
          else
            @header_print = false
          end

          if @as_json and @header_print
            @current_file.write '['.encode(@encoding)
          end

          datum = {}
          @schema.each do |col|
            datum[col.name] = @json_columns.include?(col.name) ? JrJackson::Json.load(record[col.index]) : record[col.index]
          end

          outline = "#{JrJackson::Json.dump(datum, @opts )}#{@newline}".encode(@encoding)
          @current_file_size += outline.bytesize
          @current_file.write outline
        end
      end

      def finish
        file_output.finish
      end
    end

  end
end
