	class AccessControlStep < Hydrant::Workflow::BasicStep
		def initialize(step = 'access-control', 
                               title = "Access Control", 
                               summary = "Who can access the item", 
                               template = 'access_control')
		  super
		end

		def execute context
		  mediaobject = context[:mediaobject]
	          # TO DO: Implement me
        	  logger.debug "<< Access flag = #{context[:access]} >>"
              	  mediaobject.access = context[:access]        

                  mediaobject.hidden = context[:hidden] unless context[:hidden].blank?
        
	          mediaobject.save
        	  logger.debug "<< Groups : #{mediaobject.read_groups} >>"
		  context
		end
	end
