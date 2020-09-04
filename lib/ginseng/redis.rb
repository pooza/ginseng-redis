require 'ginseng'
require 'active_support/dependencies/autoload'

module Ginseng
  module Redis
    extend ActiveSupport::Autoload

    autoload :Config
    autoload :DSN
    autoload :Environment
    autoload :Error
    autoload :Logger
    autoload :Package
    autoload :Service
    autoload :TestCase
    autoload :TestCaseFilter

    autoload_under 'test_case_filter' do
      autoload :CITestCaseFilter
    end
  end
end
