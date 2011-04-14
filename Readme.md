pgcmd
======
a beta plugin for the heroku gem to enable replication functionality

Replication
============
Heroku PostgreSQL now supports two new modes, fork and track.

Forking will give you an exact clone of an existing database up to the point when the --fork command was issued. Tracking will give you a database which follows its leader with a low latency, usually on the order of a second or two.

We've done a bunch of work behind the scenes to make everything Just Work with a few caveats. First, you can only fork and track databases of the same plan, and second you can only fork and track PostgreSQL 9.0 databases. 8.4 databases do not support this technology.

To take advantage of them, try:

* heroku addons:add heroku-postgresql:ronin --fork HEROKU_POSTGRESQL_COLOR_OF_OTHER_RONIN
* heroku addons:add heroku-postgresql:ika --track HEROKU_POSTGRESQL_COLOR_OF_OTHER_IKA

Last, if you want to convert a tracking database into a leader, use pg:promote as you would normally. It will kick the tracking database out of read-only mode and split the relationship between the two databases.

Caveats
=======
While we have made every effort to protect against any possible situation that could lead to problems with production applications and intend to release code very like this into production, we should warn you that this is beta code, and we do not recommend running commands against production databases while you have this plugin installed.

Please ensure your heroku gem is recent by running a "gem install heroku".

Changes to existing commands
============================
* For consistency with the new addons:remove notation, all pg and pgbackups namespace commands now accept the database flag in the following form: HEROKU_POSTGRESQL_COLOR.
* Commands which make no irreversible changes to your database will default to the current value of DATABASE_URL.
* pg:info and pg:wait do not take an argument, they simply operate on all databases attached to your application

Known Bugs
==========
* The help strings are not updated.
