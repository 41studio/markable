module Markable
  module ActsAsMarkable
    extend ActiveSupport::Concern

    module ClassMethods
      def markable_as(*args)
        options = args.extract_options!
        marks   = args.flatten

        Markable.set_models

        class_eval do
          class << self
            attr_accessor :__markable_marks
          end
        end

        marks = Array.wrap(marks).map!{|i| i.to_sym }

        markers = options[:by].present? ? Array.wrap(options[:by]) : :all

        self.__markable_marks ||= {}
        marks.each do |mark|
          self.__markable_marks[mark] = {
            :allowed_markers => markers
          }
        end

        class_eval do
          has_many :markable_marks, :class_name => 'Markable::Mark', :as => :markable
          include Markable::ActsAsMarkable::MarkableInstanceMethods

          def self.marked_as(mark, options = {})
            if options[:by].present?
              result = self.joins(:markable_marks).where( :marks => {
                :mark => mark, :marker_id => options[:by].id, :marker_type => options[:by].class.name
              })
              markable = self
              result.class_eval do
                define_method :<< do |object|
                  options[:by].set_mark mark, object
                  self
                end
                define_method :delete do |markable|
                  options[:by].remove_mark mark, markable
                  self
                end
              end
            else
              result = self.joins(:markable_marks).where( :marks => { :mark => mark } ).group("#{self.table_name}.id")
            end
            result
          end
        end

        self.__markable_marks.each do |mark, o|
          class_eval %(
            def self.marked_as_#{mark} options = {}
              self.marked_as :#{mark}, options
            end

            def marked_as_#{mark}? options = {}
              self.marked_as? :#{mark}, options
            end
          )
        end

        Markable.add_markable self
      end
    end

    module MarkableInstanceMethods
      def mark_as(mark, markers)
        Array.wrap(markers).each do |marker|
          Markable.can_mark_or_raise? marker, self, mark
          params = {
            :markable_id => self.id,
            :markable_type => self.class.name,
            :marker_id => marker.id,
            :marker_type => marker.class.name,
            :mark => mark
          }
          Markable::Mark.create(params) unless Markable::Mark.exists? params
        end
      end

      def marked_as?(mark, options = {})
        if options[:by].present?
          Markable.can_mark_or_raise? options[:by], self, mark
        end
        params = {
          :markable_id => self.id,
          :markable_type => self.class.name,
          :mark => mark
        }
        if options[:by].present?
          params[:marker_id] = options[:by].id
          params[:marker_type] = options[:by].class.name
        end
        Markable::Mark.exists? params
      end

      def unmark(mark, options = {})
        if options[:by].present?
          Markable.can_mark_or_raise? options[:by], self, mark
          Array.wrap(options[:by]).each do |marker|
            params = {
              :markable_id => self.id,
              :markable_type => self.class.name,
              :marker_id => marker.id,
              :marker_type => marker.class.name,
              :mark => mark
            }
            Markable::Mark.delete_all(params)
          end
        else
          params = {
            :markable_id => self.id,
            :markable_type => self.class.name,
            :mark => mark
          }
          Markable::Mark.delete_all(params)
        end
      end

      def have_marked_as_by(mark, target)
        result = target.joins(:marker_marks).where( :marks => {
          :mark => mark, :markable_id => self.id, :markable_type => self.class.name
        })
        markable = self
        result.class_eval do
          define_method :<< do |markers|
            Array.wrap(markers).each do |marker|
              marker.set_mark mark, markable
            end
            self
          end
          define_method :delete do |markers|
            Markable.can_mark_or_raise? markers, markable, mark
            Array.wrap(markers).each do |marker|
              marker.remove_mark mark, markable
            end
            self
          end
        end
        result
      end
    end
  end
end

ActiveRecord::Base.send :include, Markable::ActsAsMarkable
