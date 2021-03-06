module ModsTemplates
	extend ActiveSupport::Concern

	included do
		class_eval do
		  # Title Templates
		  define_template :title_info do |xml, title, attributes={}|
		  	opts = { primary: false }.merge(attributes)
		    attrs = opts[:type].present? ? { :type => opts[:type].to_s } : {}
		  	attrs['usage']="primary" if opts[:primary]
		    xml.titleInfo(attrs) {
		      xml.title(title)
		      xml.subTitle(opts[:subtitle]) if opts[:subtitle].present?
		    }
		  end

		  def add_title(title, attrs={}, defaults={})
		  	add_child_node(ng_xml.root, :title_info, title, defaults.merge(attrs))
		  end
		  def add_main_title(title, attrs={}); 				add_title(title, attrs, primary: true);     end
		  def add_alternative_title(title, attrs={}); add_title(title, attrs, type: :alternative); end
		  def add_translated_title(title, attrs={});  add_title(title, attrs, type: :translated);  end
		  def add_uniform_title(title, attrs={});     add_title(title, attrs, type: :uniform);     end

		  # Name Templates
		  define_template :name do |xml, name, attributes|
		  	opts = { type: 'personal', role_code: 'ctb', role_text: 'Contributor', primary: false }.merge(attributes)
		  	logger.debug([name, opts].inspect)
		  	attrs = { :type => opts[:type] }
		  	attrs['usage']="primary" if opts[:primary]
		    xml.name(attrs) {
		      xml.namePart { xml.text(name) }
		      if (opts[:role_code].present? or opts[:role_text].present?)
		        xml.role {
		          xml.roleTerm(:authority => 'marcrelator', :type => 'code') { xml.text(opts[:role_code]) } if opts[:role_code].present?
		          xml.roleTerm(:authority => 'marcrelator', :type => 'text') { xml.text(opts[:role_text]) } if opts[:role_text].present?
		        }
		      end
		    }
		    logger.debug(xml.parent.to_xml)
		  end
		  def add_creator(name, attrs={})
		  	add_child_node(ng_xml.root, :name, name, (attrs).merge(role_code: 'cre', role_text: 'Creator', primary: true))
		  end
		  def add_contributor(name, attrs={})
		  	add_child_node(ng_xml.root, :name, name, attrs)
		  end

		  # Simple Subject Templates
		  define_template(:simple_subject) do |xml, text, type| 
		  	xml.subject { xml.send(type.to_sym, text) }
	  	end
	  	def add_subject(text, type)
	  		add_child_node(ng_xml.root, :simple_subject, text, type)
	  	end
	  	def add_topical_subject(text, *args);    add_subject(text, :topic);    end
	  	def add_geographic_subject(text, *args); add_subject(text, :geographic); end
	  	def add_temporal_subject(text, *args);   add_subject(text, :temporal);   end
	  	def add_occupation_subject(text, *args); add_subject(text, :occupation); end

		  # Complex Subject Templates
	  	def add_name_subject(name, type)
	  		add_child_node(ng_xml.root.add_child('<subject/>'), :name, name, type: type)
	  	end
	  	def add_person_subject(name, *args);     add_name_subject(name, :personal);   end
	  	def add_corporate_subject(nam, *argse);  add_name_subject(name, :corporate);  end
	  	def add_occupation_subject(name, *args); add_name_subject(name, :occupation); end

		  define_template :language do |xml, code, text|
		    xml.language {
		      xml.languageTerm(:type => 'code') { xml.text(code) } if code.present?
		      xml.languageTerm(:type => 'text') { xml.text(text) } if text.present?
		    }
		  end

		  define_template :media_type do |xml,mime_type|
		    xml.physicalDescription {
		      xml.internetMediaType mime_type
		    }
		  end

		  define_template :note do |xml,text,type='general'|
		  	xml.note(:type => type) {
		  		xml.text(text)
		  	}
		  end

		  define_template :collection do |xml,collection_name|
		  	xml.relatedItem(:type => 'host') {
		  		xml.titleInfo {
		  			xml.title {
		  				xml.text(collection_name)
		  			}
		  		}
		  	}
		  end

		end
	end

end