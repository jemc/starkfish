#!ruby

require 'pp'
require 'pathname'
require 'fileutils'
require 'erb'
require 'yaml'
require 'enumerator'

require 'rdoc/rdoc'

StarkfishSuperclass = RDoc::Generator.const_defined?( "XML" ) ? RDoc::Generator::XML : Object

#
#  Starkfish RDoc HTML Generator
#  
#  $Id$
#
#  == Author/s
#  * Michael Granger (ged@FaerieMUD.org)
#  
#  == Contributors
#  * Mahlon E. Smith (mahlon@martini.nu)
#  * Eric Hodel (drbrain@segment7.net)
#  
#  == License
#  
#  :include: LICENSE
#  
class RDoc::Generator::Starkfish < StarkfishSuperclass

	RDoc::RDoc.add_generator( self )

	include ERB::Util

	# Subversion rev
	SVNRev = %$Rev$
	
	# Subversion ID
	SVNId = %$Id$

	# Path to this file's parent directory. Used to find templates and other
	# resources.
	GENERATOR_DIR = Pathname.new( __FILE__ ).expand_path.dirname

	# Release Version
	VERSION = '1.1.7'

	# Directory where generated classes live relative to the root
	CLASS_DIR = nil

	# Directory where generated files live relative to the root
	FILE_DIR = nil

	# An array of transforms to run on a method name to derive a suitable
	# anchor name. The pairs are used in pairs as arguments to gsub.
	ANAME_TRANSFORMS = [
		/\?$/,   '_p',
		/\!$/,   '_bang',
		/=$/,    '_eq',
		/^<<$/,  '_lshift',
		/^>>$/,  '_rshift',
		/\[\]=/, '_aset',
		/\[\]/,  '_aref',
		/\*\*/,  '_pow',
		/^~$/,   '_complement',
		/^!$/,   '_bang',
		/^\+@$/, '_uplus',
		/^-@$/,  '_uminus',
		/^\+$/,  '_add',
		/^-$/,   '_sub',
		/^\*$/,  '_mult',
		%r{^/$}, '_div',
		/^%$/,   '_mod',
		/^<=>$/, '_comp',
		/^==$/,  '_equal',
		/^!=$/,  '_nequal',
		/^===$/, '_eqq',
		/^>$/,   '_gt',
		/^>=$/,  '_ge',
		/^<$/,   '_lt',
		/^<=$/,  '_le',
		/^&$/,   '_and',
		/^|$/,   '_or',
		/^\^$/,  '_xor',
		/^=~$/,  '_match',
		/^!~$/,  '_notmatch',
	]


	#################################################################
	###	C L A S S   M E T H O D S
	#################################################################

	### Standard generator factory method
	def self::for( options )
		new( options )
	end


	#################################################################
	###	I N S T A N C E   M E T H O D S
	#################################################################

	### Initialize a few instance variables before we start
	def initialize( options )
		@options = options
		@template = nil
		
		template = options.template || 'starkfish'
		@template_dir = (template =~ /\A\//) ? 
			Pathname.new( template ) :
			GENERATOR_DIR + 'template/' + template
		
		configfile = @template_dir + 'config.yml'
		@config = (configfile.file?) ? YAML.load_file( configfile.to_s ) : {}
		
		@files      = []
		@classes    = []
		@hyperlinks = {}
		
		@basedir = Pathname.pwd.expand_path
		
		options.diagram = false
		
		super()
	end
	
	
	######
	public
	######

	# The output directory
	attr_reader :outputdir
	
	
	### Read the spcified To be called from ERB template to import (embed) 
	### another template
	def import( erbfile )
		erb = File.open( erbfile ) {|fp| ERb.new(fp.read) }
		return erb.run( binding() )
	end


	### Return the data section from the config file (if any)
	def data
		return @config['data']
	end
	
	
	### Output progress information if debugging is enabled
	def debug_msg( *msg )
		return unless $DEBUG
		$stderr.puts( *msg )
	end
	
	
	### Create the directories the generated docs will live in if
	### they don't already exist.
	def gen_sub_directories
		@outputdir.mkpath
	end
	

	### Copy over the stylesheet into the appropriate place in the
	### output directory.
	def write_style_sheet
		debug_msg "Copying over static files"
		staticfiles = @config['static'] || %w[rdoc.css js images]
		staticfiles = staticfiles.split( /\s+/ ) if staticfiles.is_a?( String )
		staticfiles.each do |path|
			FileUtils.cp_r( @template_dir + path, '.', :verbose => $DEBUG, :noop => $dryrun )
		end
	end
	
	

	### Build the initial indices and output objects
	### based on an array of TopLevel objects containing
	### the extracted information. 
	def generate( toplevels )
		@outputdir = Pathname.new( @options.op_dir ).expand_path( @basedir )
		if RDoc::Generator::Context.respond_to?( :build_indicies)
	    	@files, @classes = RDoc::Generator::Context.build_indicies( toplevels, @options )
		else
	    	@files, @classes = RDoc::Generator::Context.build_indices( toplevels, @options )
		end

		# Now actually write the output
		generate_xhtml( @options, @files, @classes )

	rescue StandardError => err
		debug_msg "%s: %s\n  %s" % [ err.class.name, err.message, err.backtrace.join("\n  ") ]
		raise
	end


	### No-opped
	def load_html_template # :nodoc:
	end


	### Generate output
	def generate_xhtml( options, files, classes )
		files = gen_into( @files )
		classes = gen_into( @classes )

		# Make a hash of class info keyed by class name
		classes_by_classname = classes.inject({}) {|hash, classinfo|
			hash[ classinfo[:full_name] ] = classinfo
			hash[ classinfo[:full_name] ][:outfile] =
				classinfo[:full_name].gsub( /::/, '/' ) + '.html'
			hash
		}

		# Make a hash of file info keyed by path
		files_by_path = files.inject({}) {|hash, fileinfo|
			hash[ fileinfo[:full_path] ] = fileinfo
			hash[ fileinfo[:full_path] ][:outfile] = fileinfo[:full_path] + '.html'
			hash
		}

		self.write_style_sheet
		self.generate_index( options, files_by_path, classes_by_classname )
		self.generate_class_files( options, files_by_path, classes_by_classname )
		self.generate_file_files( options, files_by_path, classes_by_classname )
	end



	#########
	protected
	#########

	### Return a list of the documented modules sorted by salience first, then by name.
	def get_sorted_module_list( classes )
		nscounts = classes.keys.inject({}) do |counthash, name|
			toplevel = name.gsub( /::.*/, '' )
			counthash[toplevel] ||= 0
			counthash[toplevel] += 1
			
			counthash
		end

		# Sort based on how often the toplevel namespace occurs, and then on the name 
		# of the module -- this works for projects that put their stuff into a 
		# namespace, of course, but doesn't hurt if they don't.
		return classes.keys.sort_by do |name| 
			toplevel = name.gsub( /::.*/, '' )
			[
				nscounts[ toplevel ] * -1,
				name
			]
		end
	end
	
	
	### Generate an index page which lists all the classes which
	### are documented.
	def generate_index( options, files, classes )
		debug_msg "Rendering the index page..."

		templatefile = @template_dir + 'index.rhtml'
		modsort = self.get_sorted_module_list( classes )
		outfile = @basedir + @options.op_dir + 'index.html'
		
		self.render_template( templatefile, binding(), outfile )
	end


	### Generate a documentation file for each class present in the
	### given hash of +classes+.
	def generate_class_files( options, files, classes )
		debug_msg "Generating class documentation in #@outputdir"
		templatefile = @template_dir + 'classpage.rhtml'
		outputdir = @outputdir

		modsort = self.get_sorted_module_list( classes )

		classes.sort_by {|k,v| k }.each do |classname, classinfo|
			debug_msg "  working on %s (%s)" % [ classname, classinfo[:outfile] ]
			outfile    = outputdir + classinfo[:outfile]
			rel_prefix = outputdir.relative_path_from( outfile.dirname )
			svninfo    = self.get_svninfo( classinfo )

			debug_msg "  rendering #{outfile}"
			self.render_template( templatefile, binding(), outfile )
		end
	end


	### Generate a documentation file for each file present in the
	### given hash of +files+.
	def generate_file_files( options, files, classes )
		debug_msg "Generating file documentation in #@outputdir"
		templatefile = @template_dir + 'filepage.rhtml'

		modsort = self.get_sorted_module_list( classes )

		files.sort_by {|k,v| k }.each do |path, fileinfo|
			outfile     = @outputdir + fileinfo[:outfile]
			debug_msg "  working on %s (%s)" % [ path, outfile ]
			rel_prefix  = @outputdir.relative_path_from( outfile.dirname )
			context     = binding()

			debug_msg "  rendering #{outfile}"
			self.render_template( templatefile, binding(), outfile )
		end
	end


	### Return a string describing the amount of time in the given number of
	### seconds in terms a human can understand easily.
	def time_delta_string( seconds )
		return 'less than a minute' if seconds < 1.minute
		return (seconds / 1.minute).to_s + ' minute' + (seconds/60 == 1 ? '' : 's') if seconds < 50.minutes
		return 'about one hour' if seconds < 90.minutes
		return (seconds / 1.hour).to_s + ' hours' if seconds < 18.hours
		return 'one day' if seconds < 1.day
		return 'about one day' if seconds < 2.days
		return (seconds / 1.day).to_s + ' days' if seconds < 1.week
		return 'about one week' if seconds < 2.week
		return (seconds / 1.week).to_s + ' weeks' if seconds < 3.months
		return (seconds / 1.month).to_s + ' months' if seconds < 1.year
		return (seconds / 1.year).to_s + ' years'
	end


	# %q$Id$"
	SVNID_PATTERN = /
		\$Id:\s 
			(\S+)\s					# filename
			(\d+)\s					# rev
			(\d{4}-\d{2}-\d{2})\s	# Date (YYYY-MM-DD)
			(\d{2}:\d{2}:\d{2}Z)\s	# Time (HH:MM:SSZ)
			(\w+)\s				 	# committer
		\$$
	/x

	### Try to extract Subversion information out of the first constant whose value looks like
	### a subversion Id tag. If no matching constant is found, and empty hash is returned.
	def get_svninfo( classinfo )
		return {} unless classinfo[:sections]
		constants = classinfo[:sections].first[:constants] or return {}
	
		constants.find {|c| c[:value] =~ SVNID_PATTERN } or return {}

		filename, rev, date, time, committer = $~.captures
		commitdate = Time.parse( date + ' ' + time )
		
		return {
			:filename    => filename,
			:rev         => Integer( rev ),
			:commitdate  => commitdate,
			:commitdelta => time_delta_string( Time.now.to_i - commitdate.to_i ),
			:committer   => committer,
		}
	end


	### Load and render the erb template in the given +templatefile+ within the specified 
	### +context+ (a Binding object) and write it out to +outfile+. Both +templatefile+ and 
	### +outfile+ should be Pathname-like objects.
	def render_template( templatefile, context, outfile )
		template_src = templatefile.read
		template = ERB.new( template_src, nil, '<>' )
		template.filename = templatefile.to_s

		output = begin
			template.result( context )
		rescue NoMethodError => err
			raise "Error while evaluating %s: %s (at %p)" % [
				templatefile.to_s,
				err.message,
				eval( "_erbout[-50,50]", context )
			]
		end

		output = self.wrap_content( output, context )

		unless $dryrun
			outfile.dirname.mkpath
			outfile.open( 'w', 0644 ) do |ofh|
				ofh.print( output )
			end
		else
			debug_msg "  would have written %d bytes to %s" %
			[ output.length, outfile ]
		end
	end


	### Load the configured wrapper file and wrap it around the given +content+.
	def wrap_content( output, context )
		wrapper = @options.wrapper || @config['wrapper'] || 'wrapper.rhtml'
		wrapperfile = (wrapper =~ /\A\//) ? 
			Pathname.new( wrapper ) :
			@template_dir + wrapper
		
		if wrapperfile.file?
			# Add 'content' to the context binding for the wrapper template
			eval( "content = %p" % [output], context )

			template_src = wrapperfile.read
			template = ERB.new( template_src, nil, '<>' )
			template.filename = templatefile.to_s

			begin
				return template.result( context )
			rescue NoMethodError => err
				raise "Error while evaluating %s: %s (at %p)" % [
					templatefile.to_s,
					err.message,
					eval( "_erbout[-50,50]", context )
				]
			end
		end

	end
	

	#######
	private
	#######

	### Given the name of a Ruby method, return a name suitable for use as target names in
	### A tags.
	def aname_from_method( methodname )
		return ANAME_TRANSFORMS.enum_slice( 2 ).inject( methodname.to_s ) do |name, xform|
			name.gsub( *xform )
		end
	end
	

end # Roc::Generator::Starkfish

# :stopdoc:

### Time constants
module TimeConstantMethods # :nodoc:

	### Number of seconds (returns receiver unmodified)
	def seconds
		return self
	end
	alias_method :second, :seconds

	### Returns number of seconds in <receiver> minutes
	def minutes
		return self * 60
	end
	alias_method :minute, :minutes

	### Returns the number of seconds in <receiver> hours
	def hours
		return self * 60.minutes
	end
	alias_method :hour, :hours

	### Returns the number of seconds in <receiver> days
	def days
		return self * 24.hours
	end
	alias_method :day, :days

	### Return the number of seconds in <receiver> weeks
	def weeks
		return self * 7.days
	end
	alias_method :week, :weeks

	### Returns the number of seconds in <receiver> fortnights
	def fortnights
		return self * 2.weeks
	end
	alias_method :fortnight, :fortnights

	### Returns the number of seconds in <receiver> months (approximate)
	def months
		return self * 30.days
	end
	alias_method :month, :months

	### Returns the number of seconds in <receiver> years (approximate)
	def years
		return (self * 365.25.days).to_i
	end
	alias_method :year, :years


	### Returns the Time <receiver> number of seconds before the
	### specified +time+. E.g., 2.hours.before( header.expiration )
	def before( time )
		return time - self
	end


	### Returns the Time <receiver> number of seconds ago. (e.g.,
	### expiration > 2.hours.ago )
	def ago
		return self.before( ::Time.now )
	end


	### Returns the Time <receiver> number of seconds after the given +time+.
	### E.g., 10.minutes.after( header.expiration )
	def after( time )
		return time + self
	end

	# Reads best without arguments:  10.minutes.from_now
	def from_now
		return self.after( ::Time.now )
	end
end # module TimeConstantMethods


# Extend Numeric with time constants
class Numeric # :nodoc:
	include TimeConstantMethods
end

