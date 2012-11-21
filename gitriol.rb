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
require 'net/sftp'
require 'pathname'
require 'getoptlong'
require 'rdoc/usage'
require File.dirname(__FILE__) + '/cmd_usage'

require 'highline/import'

def get_password(msg)
	ask(msg) { |q| q.echo = false }
end

def git(params, error_msg=nil)
	result = `git #{params}`
	if $?.exitstatus != 0 and error_msg
		error(error_msg === true ? result : error_msg)
	end
	
	result
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
		files = ftp.nlst()
	rescue Net::FTPReplyError => resp
		raise if resp.message[0,3] != '226'
	end
	
	# Filter out . and .. files
	files = files.select {|f| f != '.' and f != '..'}	
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
		puts("[t] #{path}")
		ftp.puttextfile(path.strip)
	else
		puts("[b] #{path}")
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

class Array
  def chunk(pieces=2)
    len = self.length;
    mid = (len/pieces)
    chunks = []
    start = 0
    1.upto(pieces) do |i|
      last = start+mid
      last = last-1 unless len%pieces >= i
      chunks << self[start..last] || []
      start = last+1
    end
    chunks
  end
end


def get_username_password
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
	
	return username, password
end

def make_ftp_changes(updated_files, removed_files)
	puts "logging in via FTP (#{$uri.host})"
	username, password = get_username_password

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

def make_sftp_changes(updated_files, removed_files)
	puts "logging in via SFTP (#{$uri.host})"
	username, password = get_username_password
	
	Net::SFTP.start($uri.host, username, :password => password) do |sftp|
		# First run through and create any directories.
		dirs = []
		file_dirs = updated_files.map { |f| File.dirname(f) }.uniq
		file_dirs.each do |d|
			current_dir = ''
			Pathname.new(d).each_filename do |dir|
				next if dir == '.'
				current_dir += "#{dir}/"
				dirs.push(current_dir)
			end
		end
		dirs.uniq!
		dirs.map { |d| sftp.mkdir("#{FTP_ROOT}/#{d}").wait }
		
		# Split the files into groups
		chunks = updated_files.chunk((updated_files.length / 4).to_int)
		
		chunks.each do |chunk|
			uploads = chunk.map do |f|
				sftp.upload(f, "#{FTP_ROOT}/#{f}") do |event, uploader, *args|
					case event
						when :open then puts "[up] #{f}"
					end
				end
			end
			uploads.each { |u| u.wait }
		end
		
		removed_files.map do |f| 
			puts "remove #{f}"
			sftp.remove!(f)
		end
	end
end

def make_ftpfxptls_changes(updated_files, removed_files)
	require 'ftpfxp'

	puts "logging in via FTPFXPTLS (#{$uri.host})"
	username, password = get_username_password

	Net::FTPFXPTLS.open($uri.host, username, password) do |ftpfxptls|
		ftpfxptls.passive = true
		ftpfxptls.chdir(FTP_ROOT)
		curDir = '';

		updated_files.each do |f|
			nextDir = File.dirname(f)
			if curDir != nextDir
				ftpfxptls.chdir(FTP_ROOT)
				puts "chdir #{File.dirname(f)}"
				ftp_mkdir_p(ftpfxptls, f)
				curDir = nextDir
			end

			upload_file(ftpfxptls, f)
		end

		ftpfxptls.chdir(FTP_ROOT)
		removed_files.each do |f|
			remove_file(ftpfxptls, f)
		end
	end
end

# This is the engine powering the remote changes. These could be an upload via
# FTP, SCP, or whatever; or doing a file copy.
def make_remote_changes(updated_files, removed_files)
	case $uri.scheme
		when "sftp"
			then make_sftp_changes(updated_files, removed_files)
		when "ftpfxptls"
			then make_ftpfxptls_changes(updated_files, removed_files)
		else
			make_ftp_changes(updated_files, removed_files)
	end
end

def filter_ignored_files(files)
	if CONFIG['ignore']
		files.reject {|f| CONFIG['ignore'].find {|ig| File.fnmatch(ig.strip, f)}}
	else
		files
	end
end

def save_update(to_commit)
	# We made it! Update complete; safe to update the list of updates.
	$updates[DateTime.now.to_s] = to_commit

	File.open("#{GITRIOL_REPO_DIR}#{CONFIG['name']}.yml", 'w') do |f|
		f.write $updates.to_yaml
	end
end

def make_changes(to_commit, updated_files, removed_files)
	updated_files = filter_ignored_files(updated_files)
	removed_files = filter_ignored_files(removed_files)
	
	# Check the working copy is clean.
	git('update-index --ignore-submodules --refresh', true)
	index_files = git('diff-index --cached --name-status -r --ignore-submodules HEAD --').split($/)
	if index_files.length > 0
		error('cannot deploy: your index is not up-to-date')
	end
	
	# Checkout the required commit.
	orig_head = nil
	if git('rev-parse HEAD').strip != to_commit
		orig_head = git('symbolic-ref -q HEAD').strip
		git("checkout -q #{to_commit}", 'could not detach HEAD')
	end
	
	begin
		make_remote_changes(updated_files, removed_files)
	ensure
		# Reset to original HEAD
		if orig_head
			git("symbolic-ref HEAD #{orig_head}")
			git("reset --hard", 'could not reset to orig_head')
		end
	end
	
	save_update(to_commit)
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
def load_updates(show_errors)
	# Use the project name from the config to get the list of all previous deployments.
	begin
		updates = YAML.load_file("#{GITRIOL_REPO_DIR}#{CONFIG['name']}.yml")
	rescue
		if show_errors
			error("Can't find project '#{CONFIG['name']}' in repo: #{GITRIOL_REPO_DIR}\nDo you need to gitriol init?")
		end
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

def common_setup(show_errors=true)
	$updates = load_updates(show_errors)
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
		exit unless answer_yes('no commit to upload, use HEAD (not recommended)? (y/n): ')
		to_commit = 'HEAD'
	end
	
	to_commit = git("rev-parse #{to_commit}").strip
end

def cmd_deploy
	fake = false
	
	opts = GetoptLong.new(
		['--fake', '-f', GetoptLong::NO_ARGUMENT],
		['--help', '-h', GetoptLong::NO_ARGUMENT]
	)
	
	opts.each do |opt, arg|
		case opt
			when '--fake'
				fake = true
			when '--help'
				puts CMD_DEPLOY_USAGE
				exit
		end
	end

	common_setup

	to_commit = command_line_commit
	
	# Make sure this is a fast-forward deploy
	from_commit = $updates[$updates.keys.sort.last]
	merge_bases = git("merge-base --all #{to_commit} #{from_commit}").split($/)
	
	if merge_bases.length != 1 or merge_bases.last != from_commit
		exit unless answer_yes('not fast-forward. continue? (y/n): ')
	end
	
	if fake
		save_update(to_commit)
	else
		update_to_commit(to_commit)
	end
end

def cmd_revert
	opts = GetoptLong.new(
		['--help', '-h', GetoptLong::NO_ARGUMENT]
	)
	
	opts.each do |opt, arg|
		case opt
			when '--help'
				puts CMD_REVERT_USAGE
				exit
		end
	end

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
	limit = 10
	show_all = false
	
	opts = GetoptLong.new(
		['--all', '-a', GetoptLong::NO_ARGUMENT],
		['--help', '-h', GetoptLong::NO_ARGUMENT],
		['--limit', '-l', GetoptLong::REQUIRED_ARGUMENT]
	)
	
	opts.each do |opt, arg|
		case opt
			when '--all'
				show_all = true
			when '--help'
				puts CMD_LOG_USAGE
				exit
			when '--limit'
				limit = arg
				exit
		end
	end

	common_setup
	
	str = ''
	commit_count = 0
	$updates.keys.sort.reverse_each do |date|
		commit = $updates[date]
		str += "#{DateTime.parse(date).strftime('%F %T')}:\n"
		str += git("log --pretty=oneline -n 1 --abbrev-commit #{commit}~..#{commit}").strip + "\n\n"
		
		commit_count += 1
		if commit_count >= limit and not show_all
			break
		end
	end
	
	puts str
end

def cmd_init
	opts = GetoptLong.new(
		['--help', '-h', GetoptLong::NO_ARGUMENT]
	)
	
	opts.each do |opt, arg|
		case opt
			when '--help'
				puts CMD_INIT_USAGE
				exit
		end
	end

	common_setup(false)
	if $updates != nil
		exit unless answer_yes('project exists in repo. overwrite? (y/n): ')
	end
	
	$updates = {}
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
