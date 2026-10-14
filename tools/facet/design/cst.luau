--!strict

local syntax = require("@std/syntax")
local visitor = require("@std/syntax/visitor")

export type Trivia = { tag: string, text: string }

export type Token = {
	kind: "token",
	text: string,
	leadingTrivia: { Trivia },
	trailingTrivia: { Trivia },
}

export type List<T> = { [number]: T, separators: { Token } }

export type Local = { kind: "local", name: Token, colon: Token?, annotation: Type? }

export type Group = { kind: "expr", tag: "group", openParens: Token, expression: Expr, closeParens: Token }
export type Nil = { kind: "expr", tag: "nil", token: Token }
export type Boolean = { kind: "expr", tag: "boolean", value: boolean, token: Token }
export type Number = { kind: "expr", tag: "number", value: number, token: Token }
export type Integer = { kind: "expr", tag: "integer", value: number, token: Token }
export type String = {
	kind: "expr",
	tag: "string",
	quoteStyle: "single" | "double" | "block" | "interp",
	blockDepth: number,
	value: Token,
}
export type LocalRef = { kind: "expr", tag: "local", token: Token, ["local"]: Local, upvalue: boolean }
export type Global = { kind: "expr", tag: "global", name: Token }
export type Vararg = { kind: "expr", tag: "vararg", token: Token }
export type Call = {
	kind: "expr",
	tag: "call",
	func: Expr,
	openParens: Token?,
	arguments: List<Expr>,
	closeParens: Token?,
	self: boolean,
}
export type Instantiate = { kind: "expr", tag: "instantiate", expr: Expr }
export type IndexName = { kind: "expr", tag: "indexname", expression: Expr, accessor: Token, index: Token }
export type IndexExpr = { kind: "expr", tag: "index", expression: Expr, index: Expr }
export type Function = {
	kind: "expr",
	tag: "function",
	functionKeyword: Token,
	parameters: List<Local>,
	hasVararg: boolean,
	returnAnnotation: unknown?,
	body: Block,
	endKeyword: Token,
}
export type ListItem = { kind: "list", value: Expr, separator: Token? }
export type RecordItem = { kind: "record", key: Token, equals: Token, value: Expr, separator: Token? }
export type GeneralItem = {
	kind: "general",
	indexerOpen: Token,
	key: Expr,
	indexerClose: Token,
	equals: Token,
	value: Expr,
	separator: Token?,
}
export type TableItem = ListItem | RecordItem | GeneralItem
export type Table = { kind: "expr", tag: "table", openBrace: Token, entries: { TableItem }, closeBrace: Token }
export type Unary = { kind: "expr", tag: "unary", operator: Token, operand: Expr }
export type Binary = { kind: "expr", tag: "binary", lhsOperand: Expr, operator: Token, rhsOperand: Expr }
export type Interpolated = { kind: "expr", tag: "interpolatedstring", strings: { Token }, expressions: { Expr } }
export type Cast = { kind: "expr", tag: "cast", operand: Expr, operator: Token, annotation: Type }
export type IfElse = { kind: "expr", tag: "conditional", condition: Expr, thenExpr: Expr, elseExpr: Expr }

export type Expr =
	Group
	| Nil
	| Boolean
	| Number
	| Integer
	| String
	| LocalRef
	| Global
	| Vararg
	| Call
	| Instantiate
	| IndexName
	| IndexExpr
	| Function
	| Table
	| Unary
	| Binary
	| Interpolated
	| Cast
	| IfElse

export type Block = { kind: "stat", tag: "block", statements: { Stat } }
export type Return = { kind: "stat", tag: "return", returnKeyword: Token, expressions: List<Expr> }
export type LocalStat = {
	kind: "stat",
	tag: "local",
	localKeyword: Token,
	variables: List<Local>,
	equals: Token?,
	values: List<Expr>,
}
export type TypeAlias = {
	kind: "stat",
	tag: "typealias",
	isExported: boolean,
	name: Token,
	generics: List<Generic>?,
	type: Type,
}
export type OtherStat = { kind: "stat", tag: "other" }
export type Stat = Block | Return | LocalStat | TypeAlias | OtherStat

export type Generic = { tag: "generic", name: Token }

export type TypeReference = {
	kind: "type",
	tag: "reference",
	prefix: Token?,
	name: Token,
	parameters: List<Type | TypePack>?,
}
export type TypeBoolean = { kind: "type", tag: "boolean", value: boolean, token: Token }
export type TypeString = { kind: "type", tag: "string", value: Token }
export type TypeTypeof = { kind: "type", tag: "typeof", expression: Expr }
export type TypeGroup = { kind: "type", tag: "group", type: Type }
export type TypeOptional = { kind: "type", tag: "optional", token: Token }
export type TypeUnion = { kind: "type", tag: "union", types: List<Type> }
export type TypeIntersection = { kind: "type", tag: "intersection", types: List<Type> }
export type TypeArray = { kind: "type", tag: "array", type: Type }
export type TypeIndexer = { kind: "indexer", key: Type, value: Type }
export type TypeProperty = { kind: "property", key: Token, value: Type, access: Token? }
export type TypeTableItem = TypeIndexer | TypeProperty
export type TypeTable = { kind: "type", tag: "table", entries: { TypeTableItem } }
export type FunctionTypeParameter = { name: Token?, type: Type }
export type TypeFunction = {
	kind: "type",
	tag: "function",
	generics: List<Generic>?,
	parameters: List<FunctionTypeParameter>,
	returnTypes: TypePack,
}
export type Type =
	TypeReference
	| TypeBoolean
	| TypeString
	| TypeTypeof
	| TypeGroup
	| TypeOptional
	| TypeUnion
	| TypeIntersection
	| TypeArray
	| TypeTable
	| TypeFunction

export type TypePackExplicit = { kind: "typepack", tag: "explicit", types: List<Type> }
export type TypePackOther = { kind: "typepack", tag: "generic" | "variadic" }
export type TypePack = TypePackExplicit | TypePackOther

export type ParseResult = { root: Block, eof: Token }

export type TypeTableEntry = {
	kind: "indexer" | "property",
	access: Token?,
	indexerOpen: Token?,
	key: Token | Type,
	indexerClose: Token?,
	quoteStyle: ("single" | "double")?,
	colon: Token,
	value: Type,
	separator: Token?,
}

export type TypeSingletonString = { kind: "type", tag: "string", value: Token, quoteStyle: "single" | "double" }

export type Walker = {
	visitToken: (Token) -> boolean,
	visitExprConstantString: (String) -> boolean,
	visitTypeSingletonString: (TypeSingletonString) -> boolean,
	visitExprInterpString: (Interpolated) -> boolean,
	visitTableTypeItem: (TypeTableEntry) -> boolean,
	visitExpr: (Expr) -> boolean,
	visitExprEnd: (Expr) -> (),
}

local Cst = {}

function Cst.parse(source: string): ParseResult
	return (syntax.parse(source) :: unknown) :: ParseResult
end

function Cst.parseExpr(source: string): Expr
	return (syntax.parseExpr(source) :: unknown) :: Expr
end

function Cst.walker(): Walker
	return (visitor.create() :: unknown) :: Walker
end

function Cst.visitBlock(block: Block, walker: Walker)
	local visit = (visitor.visitBlock :: unknown) :: (Block, Walker) -> ()
	visit(block, walker)
end

function Cst.visitExpression(node: Expr, walker: Walker)
	local visit = (visitor.visitExpression :: unknown) :: (Expr, Walker) -> ()
	visit(node, walker)
end

function Cst.visitType(node: Type, walker: Walker)
	local visit = (visitor.visitType :: unknown) :: (Type, Walker) -> ()
	visit(node, walker)
end

function Cst.visitToken(node: Token, walker: Walker)
	local visit = (visitor.visitToken :: unknown) :: (Token, Walker) -> ()
	visit(node, walker)
end

return table.freeze(Cst)
