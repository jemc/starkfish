Gem::Specification.new do |s|
  s.name          = 'starkfish'
  s.version       = '0.2.1' 
  s.date          = '2013-07-22'
  s.summary       = "starkfish"
  s.description   = "An aesthetically revised template for darkfish,"\
                    "the rdoc documentation generator for ruby."
  s.authors       = ["Joe McIlvain"]
  s.email         = 'joe.eli.mac@gmail.com'
  
  s.files         = Dir["{lib}/**/*", "bin/*", "LICENSE", "*.md"]
  
  s.require_path  = 'lib'
  s.homepage      = 'https://github.com/jemc/starkfish/'
  s.licenses      = "Copyright (c) Joe McIlvain. All rights reserved "
  
  s.add_dependency('rdoc', '~> 4.0')
end