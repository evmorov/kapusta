# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Kapusta::Reader do
  describe 'error messages' do
    it 'reports unexpected closing delimiters with their source position' do
      expect { Kapusta.eval('(print 1))') }
        .to raise_error(Kapusta::Reader::Error,
                        /unexpected closing delimiter '\)' at line 1, column 10/)
    end

    it 'reports unclosed opening delimiters with their source position' do
      cases = {
        '(print 1' => /unclosed opening delimiter '\(' at line 1, column 1/,
        '[1 2' => /unclosed opening delimiter '\[' at line 1, column 1/,
        '{:name "A"' => /unclosed opening delimiter '\{' at line 1, column 1/
      }

      cases.each do |source, message|
        expect { Kapusta.eval(source) }
          .to raise_error(Kapusta::Reader::Error, message)
      end
    end
  end
end
