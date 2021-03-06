# typed: true
# frozen_string_literal: true

require "packwerk/node"
require "packwerk/offense"

module Packwerk
  class NodeProcessor
    def initialize(reference_extractor:, reference_lister:, filename:, checkers:)
      @reference_extractor = reference_extractor
      @reference_lister = reference_lister
      @filename = filename
      @checkers = checkers
    end

    def call(node, ancestors:)
      case Node.type(node)
      when Node::METHOD_CALL, Node::CONSTANT
        reference = @reference_extractor.reference_from_node(node, ancestors: ancestors, file_path: @filename)
        check_reference(reference, node) if reference
      end
    end

    private

    def check_reference(reference, node)
      return nil unless (message = failed_check(reference))

      constant = reference.constant

      Packwerk::Offense.new(
        location: Node.location(node),
        file: @filename,
        message: <<~EOS
          #{message}
          Inference details: this is a reference to #{constant.name} which seems to be defined in #{constant.location}.
          To receive help interpreting or resolving this error message, see: https://github.com/Shopify/packwerk/blob/main/TROUBLESHOOT.md#Troubleshooting-violations
        EOS
      )
    end

    def failed_check(reference)
      failing_checker = @checkers.find do |checker|
        checker.invalid_reference?(reference, @reference_lister)
      end
      failing_checker&.message_for(reference)
    end
  end
end
