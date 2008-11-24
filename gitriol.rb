#! ruby
# usage: gitriol COMMAND [ARGS]
#
# common commands:
#   init - begin managing project and upload specific commit
#   deploy - deploy a specific commit
#   revert - revert a previous deployment
#   log - view recent deployments / reverts
#   password - add, change and delete project passwords


require 'yaml'
require 'net/ftp'
require 'pathname'
require 'getoptlong'
require 'rdoc/usage'
require File.dirname(__FILE__) + '/cmd_usage'

require 'highline/import'

def get_password(msg)
	ask(msg) { |q| q.echo = false }
end

def git(params)
	`git #{params}`
end

def error(msg)
	puts msg
	exit
end


USER_HOME_DIR = Gem.user_home
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

TEXT_EXTS = ['php', 'css', 'js', 'txt', 'html', 'xml', 'yml', 'as', 'htm', 'tpl', 'csv']

def upload_file(ftp, path)
	ext = File.extname(path)[1..-1]
	if ext
		ext = ext.strip.downcase
	else
		ext = ''
	end
	
	if TEXT_EXTS.index(ext) != nil
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
	username = $uri.user
	unless username
		print 'username: '
		username = STDIN.gets
	end
	
	# Get the password from (in order): the remote uri, .gitriolpasswd, run-time
	# input.
	password = $uri.password
	unless password
		password = $passwords[CONFIG['name']]
		unless password
			password = get_password('password: ')
		end
	end

	Net::FTP.open($uri.host, username, password) do |ftp|
		ftp.passive = true
		ftp.chdir(FTP_ROOT)
		curDir = '';
		updated_files.each do |f|
			nextDir = File.dirname(f)
			if curDir != nextDir
				ftp.chdir(FTP_ROOT)
				puts "chdir #{File.dirname(f)}"
				ftp_mkdir_p(ftp, f)
				curDir = nextDir
			end
			
			upload_file(ftp, f)
		end
		
		ftp.chdir(FTP_ROOT)
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

def filter_ignored_files(files)
	if CONFIG['ignore']
		files.reject {|f| CONFIG['ignore'].find {|ig| File.fnmatch(ig.strip, f)}}
	else
		files
	end
end

def make_changes(to_commit, updated_files, removed_files)
	updated_files = filter_ignored_files(updated_files)
	removed_files = filter_ignored_files(removed_files)
	
	make_remote_changes(updated_files, removed_files)
	
	# We made it! Update complete; safe to update the list of updates.
	$updates[DateTime.now.to_s] = to_commit

	File.open("#{GITRIOL_REPO_DIR}#{CONFIG['name']}.yml", 'w') do |f|
		f.write $updates.to_yaml
	end
end

# Look in the current directory for the config file.
def load_config
	if not File.exists?('gitriol.yml')
		error('Not a gitriol project')
	end
	
	begin
		config = YAML.load_file('gitriol.yml')
	rescue
		error('error loading gitriol project config')
	end
end

def load_passwords
	begin
		file = "#{USER_HOME_DIR}/.gitriolpasswd"
		if File.exists?(file)
			passwords = YAML.load_file(file)
			if passwords.class == Hash
				passwords
			else
				{}
			end
		else
			{}
		end
	rescue
		error('error loading password file')
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

	updated_files = git("diff --name-only --diff-filter=AM #{from_commit} #{to_commit}").split($/)
	removed_files = git("diff --name-only --diff-filter=D #{from_commit} #{to_commit}").split($/)
	
	make_changes(to_commit, updated_files, removed_files)
end

def common_setup
	$updates = load_updates
end

def answer_yes(msg)
	answer = ''
	while not (answer == 'y' or answer == 'n')
		print msg
		answer = gets.strip.downcase
	end
	
	answer == 'y'
end

def command_line_commit
	# Git ref to update to should now be on top.
	to_commit = ARGV.shift
	
	if !to_commit
		to_commit = CONFIG['upload']
	end
	
	if !to_commit
		exit unless answer_yes('no commit to upload, use HEAD? (y/n): ')
		to_commit = 'HEAD'
	end
	
	to_commit = git("rev-parse #{to_commit}").strip
end

def cmd_deploy
	common_setup

	to_commit = command_line_commit
	
	# Make sure this is a fast-forward deploy
	from_commit = $updates[$updates.keys.sort.last]
	merge_bases = git("merge-base --all #{to_commit} #{from_commit}").split($/)
	
	if merge_bases.length != 1 or merge_bases.last != from_commit
		exit unless answer_yes('not fast-forward. continue? (y/n): ')
	end
	
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
		puts git("log --pretty=oneline -n 1 --abbrev-commit #{commit}~..#{commit}")
		puts
	end
end

def cmd_init
	to_commit = command_line_commit
	
	updated_files = git("ls-tree --name-only -r #{to_commit}").split($/)
	removed_files = Array.new
	
	make_changes(to_commit, updated_files, removed_files)
end

def cmd_password
	delete = false
	project = nil
	
	opts = GetoptLong.new(
		['--delete', '-d', GetoptLong::NO_ARGUMENT],
		['--help', '-h', GetoptLong::NO_ARGUMENT],
		['--project', '-p', GetoptLong::REQUIRED_ARGUMENT]
	)
	
	opts.each do |opt, arg|
		case opt
			when '--delete'
				delete = true
			when '--project'
				project = arg
			when '--help'
				puts CMD_PASSWORD_USAGE
				exit
		end
	end

	unless project
		print 'project: '
		project = STDIN.gets.strip
	end
	
	# Delete or add as per users request.
	if delete
		$passwords.delete(project)
	else
		password = get_password('password: ')
		passconfirm = get_password('confirm password: ')
		
		if password != passconfirm
			error('passwords don\'t match')
		end
		
		$passwords[project] = password
	end
	
	# Ok. Now write the password file out again.
	File.open("#{USER_HOME_DIR}/.gitriolpasswd", 'w') do |f|
		f.write $passwords.to_yaml
	end	
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
$passwords = load_passwords

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
	when 'password'
		cmd_password
	else
		missing_cmd(action)
end
