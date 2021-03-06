require 'hydrant/controller/controller_behavior'

class MediaObjectsController < ApplicationController 
  include Hydrant::Workflow::WorkflowControllerBehavior
  include Hydrant::Controller::ControllerBehavior

  before_filter :enforce_access_controls
  before_filter :inject_workflow_steps, only: [:edit, :update]
  before_filter :load_player_context, only: [:show, :remove]

  layout 'hydrant'

  # Catch exceptions when you try to reference an object that doesn't exist.
  # Attempt to resolve it to a close match if one exists and offer a link to
  # the show page for that item. Otherwise ... nothing!
  rescue_from ActiveFedora::ObjectNotFoundError do |exception|
    render '/errors/unknown_pid', status: 404
  end
  
  def new
    logger.debug "<< NEW >>"
    @mediaobject = MediaObjectsController.initialize_media_object(user_key)
    @mediaobject.workflow.origin = 'web'
    @mediaobject.save(:validate => false)

    redirect_to edit_media_object_path(@mediaobject)
  end

  def custom_edit
    if ['preview', 'structure', 'file-upload'].include? @active_step
      @masterFiles = load_master_files
    end

    if 'preview' == @active_step 
      @currentStream = params[:content] ? set_active_file(params[:content]) : @masterFiles.first
      @token = @currentStream.nil? ? "" : StreamToken.find_or_create_session_token(session, @currentStream.mediapackage_id)
      @currentStreamInfo = @currentStream.stream_details(@token) rescue {}

      if (not @masterFiles.empty? and @currentStream.blank?)
        @currentStream = @masterFiles.first
        flash[:notice] = "That stream was not recognized. Defaulting to the first available stream for the resource"
      end
    end

    if 'access-control' == @active_step 
      @group_exceptions = []
      if @mediaobject.access == "limited"
        # When access is limited, group_exceptions content is stored in read_groups
        @mediaobject.read_groups.each { |g| @group_exceptions << Admin::Group.find(g).name }
        @user_exceptions = @mediaobject.read_users 
       else
        @mediaobject.group_exceptions.each { |g| @group_exceptions << Admin::Group.find(g).name }
        @user_exceptions = @mediaobject.user_exceptions 
      end

      @addable_groups = Admin::Group.non_system_groups.reject { |g| @group_exceptions.include? g.name }
    end
  end

  def show
    respond_to do |format|
      # The flash notice is only set if you are returning HTML since it makes no
      # sense in an AJAX context (yet)
      format.html do
       	if (not @masterFiles.empty? and @currentStream.blank?)
          @currentStream = @masterFiles.first
          flash[:notice] = "That stream was not recognized. Defaulting to the first available stream for the resource"
        end
        render
      end
      format.json do
        render :json => @currentStreamInfo 
      end
    end
  end

  # This sets up the delete view which is an item preview with the ability
  # to take the item out of the system for good (by POSTing to the destroy
  # action)
  def remove 
    #@previous_view = media_object_path(@mediaobject)
  end

  # Deletes a media object from the system. This needs to be somewhat robust so that
  # you can't delete an object if you do not have permission, if it does not exist, or
  # (most likely) if the 'Yes' button was accidentally submitted twice
  def destroy
    logger.debug "<< DESTROY >>"
    logger.debug "<< Media object => #{params[:id]} >>"
    logger.debug "<< Exists? #{MediaObject.exists? params[:id]} >>"
    unless params[:id].nil? or (not MediaObject.exists?(params[:id]))
      logger.debug "<< Removing PID from system >>"
      media = MediaObject.find(params[:id])
      flash[:notice] = "#{media.title} (#{params[:id]}) has been successfuly deleted"
      media.delete
    end
    logger.debug "<< Exists? #{MediaObject.exists? params[:id]} >>"
    redirect_to root_path
  end

  # Sets the published status for the object. If no argument is given then
  # it will just toggle the state.
  def update_status
    media_object = MediaObject.find(params[:id])
    authorize! :manage, media_object
    
    logger.debug "<< Status flag is #{params[:status]} >>"
    case params[:status]
      when 'publish'
        logger.debug "<< Setting user key to #{user_key} >>"
        media_object.publish!(user_key)
      when 'unpublish'
        logger.debug "<< Setting user key to nil >>"
        media_object.publish!(nil)
      when nil
        logger.debug "<< Toggling user key >>"
        new_state = media_object.published? ? nil : user_key
        media_object.publish!(new_state)        
    end

    redirect_to :back
  end

  # Sets the published status for the object. If no argument is given then
  # it will just toggle the state.
  def update_visibility
    media_object = MediaObject.find(params[:id])
    authorize! :manage, media_object
    
    logger.debug "<< Visibility flag is #{params[:status]} >>"
    case params[:status]
      when 'show'
        logger.debug "<< Setting hidden to false >>"
        media_object.hidden = false
      when 'hide'
        logger.debug "<< Setting hidden to true >>"
        media_object.hidden = true
      when nil
        logger.debug "<< Toggling visibility >>"
        new_state = media_object.hidden? ? false : true
        media_object.hidden = new_state        
    end

    media_object.save
    redirect_to :back
  end
  
  def self.initialize_media_object( user_key )
    mediaobject = MediaObject.new( avalon_uploader: user_key )
    set_default_item_permissions( mediaobject, user_key )

    mediaobject
  end

  def matterhorn_service_config
    respond_to do |format|
      format.any(:xml, :json) { render request.format.to_sym => Hydrant.matterhorn_config }
    end
  end

  protected

  def load_master_files
    logger.debug "<< LOAD MASTER FILES >>"
    logger.debug "<< #{@mediaobject.parts} >>"

    @mediaobject.parts
  end

  def load_player_context
    @mediaobject = MediaObject.find(params[:id])
    logger.debug "<< Preparing media object #{@mediaobject} >>"

    @masterFiles = load_master_files
    @currentStream = params[:content] ? set_active_file(params[:content]) : @masterFiles.first
    @token = @currentStream.nil? ? "" : StreamToken.find_or_create_session_token(session, @currentStream.mediapackage_id)
    # This rescue statement seems a bit dodgy because it catches *all*
    # exceptions. It might be worth refactoring when there are some extra
    # cycles available.
    @currentStreamInfo = @currentStream.stream_details(@token) rescue {}
 end

  # The goal of this method is to determine which stream to provide to the interface
  #
  # for immediate playback. Eventually this might be replaced by an AJAX call but for
  # now to update the stream you must do a full page refresh.
  # 
  # If the stream is not a member of that media object or does not exist at all then
  # return a nil value that needs to be handled appropriately by the calling code
  # block
  def set_active_file(file_pid = nil)
    unless (@mediaobject.parts.blank? or file_pid.blank?)
      @mediaobject.parts.each do |part|
        return part if part.pid == file_pid
      end
    end

    # If you haven't dropped out by this point return an empty item
    nil
  end  
end
