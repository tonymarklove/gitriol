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
