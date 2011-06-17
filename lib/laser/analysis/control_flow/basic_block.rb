require 'enumerator'
require 'set'
module Laser
  module SexpAnalysis
    module ControlFlow
      # Can't use the < DelegateClass(Array) syntax because of code reloading.
      class BasicBlock
        attr_accessor :name, :instructions, :successors, :predecessors
        attr_accessor :depth_first_order, :post_order_number
        def initialize(name)
          @name = name
          @instructions = []
          @successors = Set.new
          @predecessors = Set.new
          @edge_flags = Hash.new { |hash, key| hash[key] = RGL::ControlFlowGraph::EDGE_NORMAL }
        end

        # Duplicates the block, but *not* the instructions, as that's likely
        # just a waste of memory.
        def dup
          result = BasicBlock.new(name)
          result.instructions = instructions
          result.successors = successors.dup
          result.predecessors = predecessors.dup
          result
        end
        
        def duplicate_for_graph_copy(temp_lookup, insn_lookup)
          result = BasicBlock.new(name)
          result.instructions = instructions.map do |insn|
            copy = insn.deep_dup(temp_lookup, block: result)
            insn_lookup[insn] = copy
            copy
          end
          # successors/predecessors will be inserted by graph copy.
          result
        end

        def get_flags(dest)
          @edge_flags[dest]
        end

        def has_flag?(dest, flag)
          (@edge_flags[dest] & flag) > 0
        end

        def add_flag(dest, flag)
          @edge_flags[dest] |= flag
        end

        def set_flag(dest, flag)
          @edge_flags[dest] = flag
        end

        def remove_flag(dest, flag)
          @edge_flags[dest] &= ~flag
        end
        
        def delete_all_flags(dest)
          @edge_flags.delete dest
        end
        
        def is_fake?(dest)
          has_flag?(dest, RGL::ControlFlowGraph::EDGE_FAKE)
        end
        
        def is_executable?(dest)
          has_flag?(dest, RGL::ControlFlowGraph::EDGE_EXECUTABLE)
        end

        def real_successors
          successors.reject { |dest| has_flag?(dest, RGL::ControlFlowGraph::EDGE_FAKE) }
        end

        def each_real_predecessors
          return enum_for(:each_real_predecessors) unless block_given?
          @predecessors.each do |dest|
            yield dest unless dest.has_flag?(self, RGL::ControlFlowGraph::EDGE_FAKE)
          end
        end

        def real_predecessors
          predecessors.reject { |dest| dest.has_flag?(self, RGL::ControlFlowGraph::EDGE_FAKE) }
        end
        
        def normal_successors
          successors.reject { |dest| has_flag?(dest, RGL::ControlFlowGraph::EDGE_ABNORMAL) }
        end

        def normal_predecessors
          predecessors.reject { |dest| dest.has_flag?(self, RGL::ControlFlowGraph::EDGE_ABNORMAL) }
        end

        def abnormal_successors
          successors.select { |dest| has_flag?(dest, RGL::ControlFlowGraph::EDGE_ABNORMAL) }
        end

        def abnormal_predecessors
          predecessors.select { |dest| dest.has_flag?(self, RGL::ControlFlowGraph::EDGE_ABNORMAL) }
        end

        def block_taken_successors
          successors.select { |dest| has_flag?(dest, RGL::ControlFlowGraph::EDGE_BLOCK_TAKEN) }
        end

        def block_taken_predecessors
          predecessors.select { |dest| dest.has_flag?(self, RGL::ControlFlowGraph::EDGE_BLOCK_TAKEN) }
        end

        def exception_successors
          successors.select { |dest| has_flag?(dest, RGL::ControlFlowGraph::EDGE_ABNORMAL) &&
                                    !has_flag?(dest, RGL::ControlFlowGraph::EDGE_BLOCK_TAKEN) }
        end

        def exception_predecessors
          predecessors.select { |dest| dest.has_flag?(self, RGL::ControlFlowGraph::EDGE_ABNORMAL) &&
                                      !dest.has_flag?(self, RGL::ControlFlowGraph::EDGE_BLOCK_TAKEN) }
        end

        def executed_successors
          successors.select { |dest| has_flag?(dest, RGL::ControlFlowGraph::EDGE_EXECUTABLE) }
        end

        def executed_predecessors
          predecessors.select { |dest| dest.has_flag?(self, RGL::ControlFlowGraph::EDGE_EXECUTABLE) }
        end

        def unexecuted_successors
          successors.reject { |dest| has_flag?(dest, RGL::ControlFlowGraph::EDGE_EXECUTABLE) }
        end

        def unexecuted_predecessors
          predecessors.reject { |dest| dest.has_flag?(self, RGL::ControlFlowGraph::EDGE_EXECUTABLE) }
        end

        # Removes all edges from this block.
        def clear_edges
          @successors.clear
          @predecessors.clear
          self
        end

        def variables
          Set.new(instructions.map(&:explicit_targets).inject(:|))
        end
        
        # Gets all SSA Phi nodes that are in the block.
        def phi_nodes
          instructions.select { |ins| :phi == ins[0] }
        end
        
        def natural_instructions
          instructions.reject { |ins| :phi == ins[0] }
        end

        def fall_through_block?
          instructions.empty?
        end

        def remove_successor(u)
          successors.delete u
        end

        def remove_predecessor(u, fixup=true)
          if fixup
            last_insn = u.instructions.last
            if last_insn.type == :branch
              which_to_keep = last_insn[3] == self.name ? last_insn[2] : last_insn[3]
              last_insn[1].uses.delete last_insn
              last_insn.body.replace([:jump, which_to_keep])
            end
            # must update phi nodes.
            unless phi_nodes.empty?
              which_phi_arg = predecessors.to_a.index(u) + 2
              phi_nodes.each do |node|
                node.delete_at(which_phi_arg)
                if node.size == 3
                  node.replace([:assign, node[1], node[2]])
                end
              end
            end
          end
          predecessors.delete u
        end

        # Formats the block all pretty-like for Graphviz. Horrible formatting for
        # stdout.
        def to_s
          " | #{name} | \\n" + instructions.map do |ins|
            opcode = ins.first.to_s
            if ins.method_call? && Hash === ins.last
            then range = 1..-2
            else range = 1..-1
            end
            args = ins[range].map do |arg|
              if Bindings::Base === arg
              then arg.name
              else arg.inspect
              end
            end
            if ::Hash === ins.last && ins.last[:block]
              args << {block: ins.last[:block]}
            end
            [opcode, *args].join(', ')
          end.join('\\n')
        end
      end
      
      class TerminalBasicBlock < BasicBlock
        def instructions
          []
        end
      end
    end
  end
end
