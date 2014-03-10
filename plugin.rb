# name: shared-edit
# about: allow other users to co-edit your post
# version: 0.1
# authors: Benjamin Kampmann

register_asset "javascripts/shared_edit_menu.js", :client_side
register_asset "javascripts/shared_edit_controller.js", :client_side
register_asset "javascripts/shared_edit.js.handlebars", :client_side

register_css <<CSS

nav.post-controls button.shared-edit {
  float: right;
}
CSS

require_dependency 'guardian'
require_dependency 'current_user'

module SharedEditGuardian

  def has_shared_edit(post)
    editors = ::PluginStore.get("shared-edit", "#{post.id}_editors")
    editors and editors.include? @user.id
  end

  def can_edit_post?(post)
    # We override the original Guardian method to figure out our own
    return super(post) || has_shared_edit(post)
  end
end

Guardian.send :include, SharedEditGuardian

# Why do I have to do this? Rails, you are weird!
module ::SharedEditPlugin end
SharedEditPlugin = SharedEditPlugin

after_initialize do
  # Rails Engine for managing sharing of edits
  module SharedEditPlugin
    class Engine < ::Rails::Engine
      engine_name "shared_edit_plugin"
      isolate_namespace SharedEditPlugin
    end

    class SharedEditController < ActionController::Base
      include CurrentUser

      before_filter :can_change_share_edit?

      def can_change_share_edit?
        if current_user.nil?
          render status: :forbidden, json: false
          return
        end

        if params[:post_id].nil?
          render status: 400, json: false
          return
        end

        @post = Post.find(params[:post_id])
        if @post.blank?
          render status: 404, json: false
          return
        end
        if current_user.id != @post.user_id and !current_user.staff
          render status: :forbidden, json: false
          return
        end
      end

      def index
        editors = ::PluginStore.get("shared-edit", "#{@post.id}_editors")

        users = User.where(id: editors).reject(&:blank?)

        user_fields = [:id, :username, :use_uploaded_avatar, :upload_avatar_template, :uploaded_avatar_id]
        user_fields << :name if SiteSetting.enable_names?

        render json: users.as_json(only: user_fields, methods: :avatar_template)
      end

      def set
        user_ids =
          if !params[:user_ids]
            []
          else
            params[:user_ids].split(",").map {|x| x.to_i}
          end
        ::PluginStore.set("shared-edit", "#{@post.id}_editors", user_ids)
        render json: true
      end
    end
  end

  SharedEditPlugin::Engine.routes.draw do
   get '/' => 'shared_edit#index'
   put '/' => 'shared_edit#set'
  end

  Discourse::Application.routes.append do
   mount ::SharedEditPlugin::Engine, at: '/shared_edit'
  end
end