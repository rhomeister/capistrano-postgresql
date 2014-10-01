require 'capistrano/postgresql/helper_methods'
require 'capistrano/postgresql/password_helpers'
require 'capistrano/postgresql/psql_helpers'

include Capistrano::Postgresql::HelperMethods
include Capistrano::Postgresql::PasswordHelpers
include Capistrano::Postgresql::PsqlHelpers

namespace :load do
  task :defaults do
    set :pg_database, -> { "#{fetch(:application)}_#{fetch(:stage)}" }
    set :pg_user, -> { fetch(:pg_database) }
    set :pg_ask_for_password, false
    set :pg_password, -> { ask_for_or_generate_password }
    set :pg_system_user, 'postgres'
    set :pg_system_db, 'postgres'
    # template only settings
    set :pg_templates_path, 'config/deploy/templates'
    set :pg_pool, 5
    set :pg_encoding, 'unicode'
    set :pg_host, 'localhost'
  end
end

namespace :postgresql do

  # undocumented, for a reason: drops database. Use with care!
  task :remove_all do
    on release_roles :all do
      if test "[ -e #{database_yml_file} ]"
        execute :rm, database_yml_file
      end
    end

    on primary :db do
      if test "[ -e #{archetype_database_yml_file} ]"
        execute :rm, archetype_database_yml_file
      end
    end

    on roles :db do
      psql '-c', %Q{"DROP database #{fetch(:pg_database)};"}
      psql '-c', %Q{"DROP user #{fetch(:pg_user)};"}
    end
  end

  desc 'Create DB user'
  task :create_db_user do
    on roles :db do
      next if db_user_exists? fetch(:pg_user)
      unless psql '-c', %Q{"CREATE user #{fetch(:pg_user)} WITH password '#{fetch(:pg_password)}';"}
        error 'postgresql: creating database user failed!'
        exit 1
      end
    end
  end

  desc 'Create database'
  task :create_database do
    on roles :db do
      next if database_exists? fetch(:pg_database)
      unless psql '-c', %Q{"CREATE database #{fetch(:pg_database)} owner #{fetch(:pg_user)};"}
        error 'postgresql: creating database failed!'
        exit 1
      end
    end
  end

  # This task creates the archetype database.yml file on the primary db server. This is done once when a
  # new DB user is created.
  desc 'Generate database.yml archetype'
  task :generate_database_yml_archetype do
    on roles :db, primary: true do
      next if test "[ -e #{archetype_database_yml_file} ]"
      execute :mkdir, '-pv', File.dirname(archetype_database_yml_file)
      upload! pg_template('postgresql.yml.erb'), archetype_database_yml_file
    end
  end

  # This task copies the archetype database file on the primary db server to all clients. This is done on
  # every setup, to ensure new servers get a copy as well.
  desc 'Copy archetype database.yml from primary db server to clients'
  task :generate_database_yml do
    database_yml_contents = nil
    on primary :db do
      database_yml_contents = download! archetype_database_yml_file
    end

    on release_roles :all do
      next if test "[ -e #{database_yml_file} ]"
      execute :mkdir, '-pv', shared_path.join('config')
      upload! StringIO.new(database_yml_contents), database_yml_file
    end
  end

  task :database_yml_symlink do
    set :linked_files, fetch(:linked_files, []).push('config/database.yml')
  end

  after 'deploy:started', 'postgresql:database_yml_symlink'

  desc 'Postgresql setup tasks'
  task :setup do
    invoke "postgresql:create_db_user"
    invoke "postgresql:create_database"
    invoke "postgresql:generate_database_yml_archetype"
    invoke "postgresql:generate_database_yml"
  end
end

desc 'Server setup tasks'
task :setup do
  invoke "postgresql:setup"
end
