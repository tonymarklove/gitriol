#! ruby
# usage: gitriol COMMAND [ARGS]
#
# common commands:
#   deploy
#   revert


require 'yaml'
require 'net/ftp'
require 'pathname'
require 'getoptlong'
require 'rdoc/usage'

require 'Win32/console'

def get_password(msg)
	print msg
	
	str = ''
	include Win32::Console::Constants
	stdin = Win32::Console.new(STD_INPUT_HANDLE)

	while ch = stdin.Input
		break if ch[5] == 13
		str += ch[5].chr if ch[1] == 1
	end
	
	puts
	str.strip
end

def git(params)
	`git #{params}`
end

def error(msg)
	puts msg
	exit
end



GITRIOL_REPO_DIR = ENV['GITRIOL_REPO'] or error('no gitriol repo defined')

def ftp_mkdir_p(ftp, path)
	Pathname.new(File.dirname(path)).each_filename do |dir|
		next if dir == '.'
		
		begin
			ftp.mkdir(dir) unless ftp.nlst.index(dir)
		rescue Net::FTPReplyError
			ftp.mkdir(dir)
		end
		ftp.chdir(dir)
	end
end


def nlst(ftp)
	begin
		ftp.nlst
	rescue Net::FTPReplyError
	end
end

def nlst_all(ftp)
	files = []
	begin
		ftp.retrlines('NLST -A') do |l|
			files.push(l)
	end
	rescue Net::FTPReplyError => resp
		raise if resp.message[0,3] != '226'
	end
	return files
end

TEXT_EXTS = ['php', 'css', 'js', 'txt', 'html', 'xml']

def upload_file(ftp, path)
	ftp.chdir(FTP_ROOT)
	ftp_mkdir_p(ftp, path)
	
	if TEXT_EXTS.index(File.extname(path)[1..-1].strip.downcase) != nil
		puts("text mode: #{path}")
		ftp.puttextfile(path.strip)
	else
		puts("binary mode: #{path}")
		ftp.putbinaryfile(path.strip)
	end
end

def remove_file(ftp, path)
	dirs = []
	Pathname.new(File.dirname(path)).each_filename do |dir|
		next if dir == '.'
		dirs.push(dir)
	end

	ftp.chdir(FTP_ROOT)
	puts "remove: #{path}"
	ftp.delete(path)
	
	# Now look through all directories in the path and delete the empty ones.
	ftp.chdir(FTP_ROOT)
	ftp.chdir(File.dirname(path))
	
	dirs.reverse_each do |dir|
		all = nlst_all(ftp)
		break if all.length > 0
		ftp.chdir('..')
		puts "rmdir #{ftp.pwd}/#{dir}"
		ftp.rmdir(dir)
	end
end

# Replace the hash to_yaml function to write in sorted order
class Hash
	def to_yaml( opts = {} )
		YAML::quick_emit( object_id, opts ) do |out|
			out.map( taguri, to_yaml_style ) do |map|
				sort.each do |k, v|
					map.add( k, v )
				end
			end
		end
	end
end

def make_ftp_changes(updated_files, removed_files)
	# Get username and password
	puts "#{$uri.host} login:"
	print 'username: '
	username = STDIN.gets
	password = get_password('password: ')

	Net::FTP.open($uri.host, username, password) do |ftp|
		ftp.chdir(FTP_ROOT)
		updated_files.each do |f|
			upload_file(ftp, f)
		end
		
		removed_files.each do |f|
			remove_file(ftp, f)
		end
	end
end

# This is the engine powering the remote changes. These could be an upload via
# FTP, SCP, or whatever; or doing a file copy.
def make_remote_changes(updated_files, removed_files)
	make_ftp_changes(updated_files, removed_files)
end

def make_changes(to_commit, updated_files, removed_files)
	make_remote_changes(updated_files, removed_files)
	
	# We made it! Update complete; safe to update the list of updates.
	$updates[DateTime.now.to_s] = to_commit

	File.open("#{GITRIOL_REPO_DIR}#{CONFIG['name']}.yml", 'w') do |f|
		f.write $updates.to_yaml
	end
end

# Look in the current directory for the config file.
def load_config
	begin
		config = YAML.load_file('gitriol.yml')
	rescue
		error('Not a gitriol project')
	end
end

# Load all the previously deployed updates
def load_updates
	# Use the project name from the config to get the list of all previous deployments.
	begin
		updates = YAML.load_file("#{GITRIOL_REPO_DIR}#{CONFIG['name']}.yml")
	rescue
		error("Can't find project '#{CONFIG['name']}' in repo: #{GITRIOL_REPO_DIR}\nDo you need to gitriol init?")
	end
end

def update_to_commit(to_commit)
	from_commit = $updates[$updates.keys.sort.last]

	if to_commit == from_commit
		puts 'no changes'
		exit
	end

	puts "changes: #{from_commit[0,6]} -> #{to_commit[0,6]}"

	updated_files = git("diff --name-only --diff-filter=AM #{from_commit} #{to_commit}")
	removed_files = git("diff --name-only --diff-filter=D #{from_commit} #{to_commit}")
	
	make_changes(to_commit, updated_files, removed_files)
end

def common_setup
	$updates = load_updates
end

def command_line_commit
	# Git ref to update to should now be on top.
	to_commit = ARGV.shift
	if to_commit
		to_commit = git("rev-parse #{to_commit}").strip
	else
		to_commit = git('rev-parse HEAD').strip
	end
end

def cmd_deploy
	common_setup
=begin example option parser
	opts = GetoptLong.new(
		['--apple', '-a', GetoptLong::NO_ARGUMENT]
	)
	
	opts.each do |opt, arg|
		case opt
			when '--apple'
				puts 'apple'
		end
	end
=end

	to_commit = command_line_commit
	update_to_commit(to_commit)
end

def cmd_revert
	common_setup
	
	# Top of the stack should now be either a date or an integer number of steps
	# back.
	revert = ARGV.shift
	error('nothing to revert to') unless revert
	
	# Figure out if this is a date or an integer.
	if /^\d+$/ === revert
		to_commit = $updates[$updates.keys.sort[-(revert.to_i+1)]]
	else
		date = DateTime.parse(revert)
		$updates.keys.sort.each do |key|
			pd = DateTime.parse(key)
			break if date < pd
			to_commit = $updates[key]
		end
	end
	
	update_to_commit(to_commit)
end

def cmd_log
	common_setup
	
	$updates.keys.sort.each do |date|
		commit = $updates[date]
		puts "#{DateTime.parse(date).strftime('%F %T')}:"
		puts git("log --pretty=oneline --abbrev-commit #{commit}~..#{commit}")
		puts
	end
end

def cmd_init
	to_commit = command_line_commit
	
	updated_files = git("ls-tree --name-only -r #{to_commit}")
	removed_files = Array.new
	
	make_changes(to_commit, updated_files, removed_files)
end

def missing_cmd(cmd)
	if cmd
		puts "'#{cmd}' is not a gitriol command"
	else
		RDoc::usage
	end
end

# Run the program.
CONFIG = load_config
$updates = {}

$uri = URI.parse(CONFIG['remote'])
FTP_ROOT = $uri.path

action = ARGV.shift

case action
	when 'deploy'
		cmd_deploy
	when 'revert'
		cmd_revert
	when 'log'
		cmd_log
	when 'init'
		cmd_init
	else
		missing_cmd(action)
end
