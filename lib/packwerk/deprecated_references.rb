# typed: true
# frozen_string_literal: true

require "sorbet-runtime"
require "yaml"

require "packwerk/reference"
require "packwerk/reference_lister"
require "packwerk/violation_type"

module Packwerk
  class DeprecatedReferences
    extend T::Sig
    include ReferenceLister

    def initialize(package, filepath)
      @package = package
      @filepath = filepath
      @new_entries = {}
    end

    sig do
      params(reference: Packwerk::Reference, violation_type: ViolationType)
        .returns(T::Boolean)
        .override
    end
    def listed?(reference, violation_type:)
      violated_constants_found = deprecated_references.dig(reference.constant.package.name, reference.constant.name)
      return false unless violated_constants_found

      violated_constant_in_file = violated_constants_found.fetch("files", []).include?(reference.relative_path)
      return false unless violated_constant_in_file

      violated_constants_found.fetch("violations", []).include?(violation_type.serialize)
    end

    def add_entries(reference, violation_type)
      package_violations = @new_entries.fetch(reference.constant.package.name, {})
      entries_for_file = package_violations[reference.constant.name] ||= {}

      entries_for_file["violations"] ||= []
      entries_for_file["violations"] << violation_type

      entries_for_file["files"] ||= []
      entries_for_file["files"] << reference.relative_path.to_s

      @new_entries[reference.constant.package.name] = package_violations
    end

    def dump
      if @new_entries.empty?
        File.delete(@filepath) if File.exist?(@filepath)
      else
        prepare_entries_for_dump
        message = <<~MESSAGE
          # This file contains a list of dependencies that are not part of the long term plan for #{@package.name}.
          # We should generally work to reduce this list, but not at the expense of actually getting work done.
          #
          # You can regenerate this file using the following command:
          #
          # bundle exec packwerk update #{@package.name}
        MESSAGE
        File.open(@filepath, "w") do |f|
          f.write(message)
          f.write(@new_entries.to_yaml)
        end
      end
    end

    private

    def prepare_entries_for_dump
      @new_entries.each do |package_name, package_violations|
        package_violations.each do |_, entries_for_file|
          entries_for_file["violations"].sort!.uniq!
          entries_for_file["files"].sort!.uniq!
        end
        @new_entries[package_name] = package_violations.sort.to_h
      end

      @new_entries = @new_entries.sort.to_h
    end

    def deprecated_references
      @deprecated_references ||= if File.exist?(@filepath)
        YAML.load_file(@filepath) || {}
      else
        {}
      end
    end
  end
end
