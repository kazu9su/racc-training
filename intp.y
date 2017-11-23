class IntpParser

prechigh
  nonassoc UMINUS
  left     '*' '/'
  left     '+' '-'
preclow

rule

  program : stmt_list
            {
              result = RootNode.new( val[0], @intp )
            }

  stmt_list :
            {
              result = []
            }
          | stmt_list stmt EOL
            {
              result.push val[1]
            }
          | stmt_list EOL

  stmt    : expr
          | assign
          | IDENT realprim
            {
              result = FuncallNode.new( @fname, val[0][0], val[0][1], [val[1]] )
            }
          | if_stmt
          | while_stmt
          | defun

  defun   : DEF IDENT param EOL stmt_list END
            {
              result = DefNode.new( @fname, val[0][0], val[1][1],
                Function.new(@fname, val[0][0], val[2], val[4]) )
            }

  param   : '(' name_list ')'
            {
              result = val[1]
            }
          | '(' ')'
            {
              result = []
            }
          |
            {
              result = []
            }

  name_list : IDENT
              {
                result = [ val[0][1] ]
              }
            | name_list ',' IDENT
              {
                result.push val[2][1]
              }

  if_stmt : IF stmt THEN EOL stmt_list else_stmt END
            {
              result = IfNode.new( @fname, val[0][0], val[1], val[4], val[5] )
            }

  else_stmt : ELSE EOL stmt_list
            {
              result = val[2]
            }
          |
            {
              result = nil
            }

  while_stmt : WHILE stmt DO EOL stmt_list END
            {
              result = WhileNode.new( @fname, val[0][0], val[1], val[4] )
            }

  assign  : IDENT '=' expr
            {
              result = AssignNode.new( @fname, val[0][0], val[0][1], val[2] )
            }

  expr    : expr '+' expr
            {
              result = FuncallNode.new( @fname, val[0].lineno, '+', [val[0], val[2]] )
            }
          | expr '-' expr
            {
              result = FuncallNode.new( @fname, val[0].lineno, '-', [val[0], val[2]] )
            }
          | expr '*' expr
            {
              result = FuncallNode.new( @fname, val[0].lineno, '*', [val[0], val[2]] )
            }
          | expr '/' expr
            {
              result = FuncallNode.new( @fname, val[0].lineno, '/', [val[0], val[2]] )
            }
          | primary

  primary : realprim
          | '(' expr ')'
            {
              result = val[1]
            }
          | '-' expr =UMINUS
            {
              result = FuncallNode.new( @fname, val[0].lineno, '-@', [val[1]] )
            }

  realprim : IDENT
            {
              result = VarRefNode.new( @fname, val[0][0], val[0][1] )
            }
          | NUMBER
            {
              result = LiteralNode.new( @fname, *val[0] )
            }
          | STRING
            {
              result = StringNode.new( @fname, *val[0] )
            }
          | funcall

  funcall : IDENT '(' args ')'
            {
              result = FuncallNode.new( @fname, val[0][0], val[0][1], val[2] )
            }
          | IDENT '(' ')'
            {
              result = FuncallNode.new( @fname, val[0][0], val[0][1], [] )
            }

  args    : expr
            {
              result = val
            }
          | args ',' expr
            {
              result.push val[2]
            }

end

---- inner

def initialize
  @intp = Intp.new
end

RESERVED = {
  'if' => :IF,
  'else' => :ELSE,
  'while' => :WHILE,
  'then' => :THEN,
  'do' => :DO,
  'end' => :END,
  'def' => :DEF,
}

def parse( f, fname )
  @q = []
  @fname = fname
  lineno = 1

  f.each do |line|
    until line.empty? do
      case line
      when /\A\s+/, /\A\#.*/
        ;
      when /\A[a-zA-Z_]\w*/
        word = $&
        @q.push [RESERVED[word]||:IDENT, [lineno, word.intern]]
      when /\A\d+/
        @q.push [ :NUMBER, [lineno, $&.to_i] ]
      when /\A"(?:[^"\\]+|\\.)*"/, /\A'(?:[^'\\]+|\\.)*'/
        @q.push [ :STRING, [lineno, eval($&)] ]
      when /\A./
        @q.push [ $&, [lineno, $&] ]
      else
        raise RuntimeError, 'must not happen'
      end
      line = $'
    end
    @q.push [ :EOL, [lineno, nil] ]
  end
  @q.push [ false, '$' ]

  do_parse
end

def next_token
  @q.shift
end

def on_error( t, v, values )
  if v then
    line = v[0]
    v = v[1]
  else
    line = 'last'
  end
  raise Racc::ParseError,
        "#{@fname}:#{line}: sintax error on #{v.inspect}"
end

---- footer

class IntpError < StandardError; end
class IntpArgumentError < StandardError; end

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
    while @condition.evaluate( intp ) != 0 do
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

class Intp

  def initialize
    @ftab = {}
    @obj = Object.new
    @stack = []
    @stack.push IntpFrame.new '(toplevel)'
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
      frame = IntpFrame.new( fname )
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

class IntpFrame

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
      intp.call_function_or( @funcname, arg ) do
        if arg.empty? or not arg[0].respond_to? @funcname then
          intp_error! "undefined function #{@funcname.id2name}"
        end
        recv = arg.shift
        recv.send @funcname, *arg
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
      tree = IntpParser.new.parse( f, ARGV[0] )
    end
  else
    tree = IntpParser.new.parse( $stdin, '-' )
  end

  tree.evaluate
rescue Racc::ParseError, IntpError
  $stderr.puts "#{File.basename $0}: #{$!}"
  exit 1
end
