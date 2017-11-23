# frozen_string_literal: true

class Intp::Parser

prechigh
  nonassoc UMINUS
  left     '*' '/'
  left     '+' '-'
  nonassoc EQ
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
          | expr EQ expr
            {
              result = FuncallNode.new( @fname, val[0].lineno, '==', [val[0], val[2]] )
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
          | TRUE
            {
              result = LiteralNode.new( @fname, *val[0] )
            }
          | FALSE
            {
              result = LiteralNode.new( @fname, *val[0] )
            }
          | NIL
            {
              result = LiteralNode.new( @fname, *val[0] )
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
  @intp = Core.new
end

RESERVED = {
  'if' => :IF,
  'else' => :ELSE,
  'while' => :WHILE,
  'then' => :THEN,
  'do' => :DO,
  'end' => :END,
  'def' => :DEF,
  'true' => :TRUE,
  'false' => :FALSE,
  'nil' => :NIL,
}

RESERVED_V = {
  'true' => true,
  'false' => false,
  'nil' => nil,
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
        @q.push [RESERVED[word]||:IDENT, [lineno,
            if RESERVED_V.key? word
              then RESERVED_V[word]
            else word.intern end]]
      when /\A\d+/
        @q.push [ :NUMBER, [lineno, $&.to_i] ]
      when /\A"(?:[^"\\]+|\\.)*"/, /\A'(?:[^'\\]+|\\.)*'/
        @q.push [ :STRING, [lineno, eval($&)] ]
      when /\A==/
        @q.push [ :EQ, [lineno, '=='] ]
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

