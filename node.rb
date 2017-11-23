# frozen_string_literal: true

module Intp
  class IntpError < StandardError; end
  class IntpArgumentError < IntpError; end
  class Node

    def initialize( fname, lineno )
      @filename = fname
      @lineno = lineno
    end

    attr :filename
    attr :lineno

    def exec_list( nodes, intp )
      v = nil
      nodes.each {|i| v = i.evaluate( intp ) }
      v
    end

    def intp_error!( msg )
      raise IntpError, "in #{filename}:#{lineno}: #{msg}"
    end

    def inspect
      "#{type.name}/#{lineno}"
    end
  end

  class RootNode < Node

    def initialize( tree, intp )
      super nil, nil
      @tree = tree
      @intp = intp
    end

    def evaluate
      exec_list @tree, @intp
    end
  end

  class FuncallNode < Node

    def initialize( fname, lineno, func, args )
      super fname, lineno
      @func = func
      @args = args
    end

    def evaluate( intp )
      arg = @args.collect {|i| i.evaluate }
      recv = Object.new
      if recv.respond_to? @func, true then
        ;
      elsif arg[0] and arg[0].respond_to? @func then
        recv = arg.shift
      else
        intp_error! "undefined method #{@func.id2name}"
      end
      recv.send @func, *arg
    end
  end

  class IfNode < Node

    def initialize( fname, lineno, cond, tstmt, fstmt )
      super fname, lineno
      @condition = cond
      @tstmt = tstmt
      @fstmt = fstmt
    end

    def evaluate( intp )
      if @condition.evaluate intp then
        exec_list @tstmt, intp
      else
        exec_list @fstmt, intp if @fstmt
      end
    end
  end

  class WhileNode < Node

    def initialize( fname, lineno, cond, body )
      super fname, lineno
      @condition = cond
      @body = body
    end

    def evaluate( intp )
      while @condition.evaluate( intp ) do
        exec_list @body, intp
      end
    end
  end

  class AssignNode < Node

    def initialize( fname, lineno, vname, val )
      super fname, lineno
      @vname = vname
      @val = val
    end

    def evaluate( intp )
      intp.frame[ @vname ] = @val.evaluate intp
    end
  end

  class VarRefNode < Node
    def initialize( fname, lineno, vname )
      super fname, lineno
      @vname = vname
    end

    def evaluate( intp )
      if intp.frame.lvar? @vname then
        intp.frame[ @vname ]
      else
        intp.call_function_or( @vname, [] ) do
          intp_error! "unknown method or local variable #{@vname.id2name}"
        end
      end
    end
  end

  class StringNode < Node

    def initialize( fname, lineno, str )
      super fname, lineno
      @val = str
    end

    def evaluate( intp )
      @val.dup
    end
  end

  class LiteralNode < Node

    def initialize( fname, lineno, str )
      super fname, lineno
      @val = str
    end

    def evaluate( intp )
      @val
    end
  end

  class Core

    def initialize
      @ftab = {}
      @obj = Object.new
      @stack = []
      @stack.push Frame.new '(toplevel)'
    end

    def frame
      @stack[-1]
    end

    def define_function( fname, node )
      if @ftab.key? fname then
        raise IntpError,
          "function #{fname.id2name} defined twice"
      end
      @ftab[ fname ] = node
    end

    def call_function_or( fname, args )
      call_intp_function_or( fname, args ) do
        call_ruby_toplevel_or( fname, args ) do
          yield
        end
      end
    end

    def call_intp_function_or( fname, args )
      if func = @ftab[ fname ] then
        frame = Frame.new( fname )
        @stack.push frame
        func.call self, frame, args
        @stack.pop
      else
        yield
      end
    end

    def call_ruby_toplevel_or( fname, args )
      if @obj.respond_to? fname, true then
        @obj.send fname, *args
      else
        yield
      end
    end
  end

  class Frame

    def initialize( fname )
      @fname = fname
      @lvars = {}
    end

    attr :fname

    def lvar?( name )
      @lvars.key? name
    end

    def []( key )
      @lvars[ key ]
    end

    def []=( key, val )
      @lvars[ key ] = val
    end
  end

  class DefNode < Node

    def initialize( file, lineno, fname, func )
      super file, lineno
      @funcname = fname
      @funcobj = func
    end

    def evaluate( intp )
      intp.define_function @funcname, @funcobj
    end
  end

  class Function < Node

    def initialize( file, lineno, params, body )
      super file, lineno
      @params = params
      @body = body
    end

    def call( intp, frame, args )
      unless args.size == @params.size then
        raise IntpArgumentError,
          sprintf('wrong # of arg for %s() (%d for %d)',
                  frame.name, args.size, @params.size)
      end
      args.each_with_index do |v, i|
        frame[ @params[i] ] = v
      end
      exec_list @body, intp
    end
  end

  class FuncallNode < Node

    def initialize( file, lineno, func, args )
      super file, lineno
      @funcname = func
      @args = args
    end

    def evaluate( intp )
      arg = @args.collect {|i| i.evaluate intp }

      begin
        intp.call_intp_function_or( @funcname, arg ) do
          if arg.empty? or not arg[0].respond_to? @funcname then
            intp.call_ruby_toplevel_or( @funcname, arg ) do
              intp_error! "undefined function #{@funcname.id2name}"
            end
          else
            recv = arg.shift
            recv.send @funcname, *arg
          end
        end
      rescue IntpArgumentError, ArgumentError
        intp_error! $!.message
      end
    end
  end

  begin
    tree = nil
    if ARGV[0] then
      File.open( ARGV[0] ) do |f|
        tree = Intp::Parser.new.parse( f, ARGV[0] )
      end
    else
      tree = Intp::Parser.new.parse( $stdin, '-' )
    end

    tree.evaluate
  rescue Racc::ParseError, IntpError
    $stderr.puts "#{File.basename $0}: #{$!}"
    exit 1
  end
end
