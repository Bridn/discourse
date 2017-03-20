require 'rails_helper'
require 'stylesheet/compiler'

describe Stylesheet::Compiler do
  it "can compile all our assets" do
    Stylesheet::Compiler.compile("desktop")
  end
end


