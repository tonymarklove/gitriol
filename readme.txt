Gitriol
----

Gitriol is a file upload tool written in Ruby that uses Git to manage
changesets. Gitriol uses your project's Git repository to find the diffs between
deployments, then uploads those files that have changed.

- Deploy your app with a single command.
- Rewind to a previous deployment state if anything goes wrong.


When should I NOT use Gitriol?
---

Gitriol is a farily simple tool aimed simply at uploading files. Although some
features may be added in the future, it currently does not allow you to run
scripts or other commands that more advanced build/deployment tools allow.

The reason I built Gitriol rather than using something such as Capistrano is
simply because I don't always have SSH access to the servers I use, and
therefore needed something that worked with FTP.


I don't use Git, can I still use Gitriol?
---

Not in it's current state.

The initial design was to keep the SCM layer partitioned from the rest of the
system so that other SCMs could be added later. As improvements have been made,
however, Gitriol has come to depend on more Git features, making the
separation more difficult.


Possible Future Features
---

- Support other SCMs. (Esp. SVN and HG.)
- Support other file transfer protocols: SSH, SFTP.
- Provide scripting hooks at various stages.


Getting Started
---

There are a couple of step you need to take when you first install Gitriol:


1. Install Ruby
--


2. Install Gitriol
--
Which simply means cloning it, or unzipping it somewhere.


3. Create Store Directory
--
Gitriol keeps track of versions by writing YAML files to a store directory.
This directory can be created anywhere you like as long as Gitriol has write
access.

Finally you need to create the GITRIOL_REPO environment variable which points
to the directory you have just created. (Make sure to include a trailing slash!)



Creating a Project
---

1. Add gitriol.yml
--
Gitriol's project config file is called gitriol.yml and sits in the root
directory of your project.

See the config.txt file for full details about configuring gitriol.


2. Initialize the project
--
Run "gitriol.rb init" to create the project and make the first deployment.


3. Deploy
--
Each time you want to upload your changes run "gitriol.rb deploy".
