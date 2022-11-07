### A Pluto.jl notebook ###
# v0.19.11

using Markdown
using InteractiveUtils

# ╔═╡ dd850c42-627d-4885-9516-857a2883fa55
begin
import ManifoldsBase
import Graphs
import Plots
import Manifolds
import LinearAlgebra
import Random, Distributions
end

# ╔═╡ c935e5a1-dff5-435a-8631-49f893e4288a
begin

function ProdManifoldExp(M,ProductMan)
	parts = []
	for i in 1:length(ProductMan.parts)
		push!(parts,Manifolds.exp_lie(M[i],ProductMan.parts[i]))
	end
	return Manifolds.ProductRepr(parts[1],parts[2],parts[3],parts[4],parts[5])
end

function ProdManifoldLog(M,ProductMan)
	parts = []
	for i in 1:length(ProductMan.parts)
		push!(parts,Manifolds.log_lie(M[i],ProductMan.parts[i]))
	end
	return Manifolds.ProductRepr(parts[1],parts[2],parts[3],parts[4],parts[5])
end
	
function createSE2(theta,x,y)
	[[cos(theta),sin(theta),0] [-sin(theta),cos(theta),0] [x,y,1]]
end
function createSO2(theta)
	return [[cos(theta),sin(theta)] [-sin(theta),cos(theta)]]
end
	
function getEpsilon(group)
	if group == "SE"
		P= [[0.1,0.5,-0.2] [0.5,4,-1] [-0.2,-1,1]]
		epsilon=[0,0,0]
		d= Distributions.MvNormal(epsilon,P)
		return rand(d)
	end 
	if group == "SO"
		P= 0.25*ones(Int8,1,1)
		epsilon=[0]
		d= Distributions.MvNormal(epsilon,P)
		rand(d)
	end
end

function createIdentitySnake()
	s1 = createSE2(0,0,0)
	s2 = createSO2(0)
	return Manifolds.ProductRepr(s1,s2,s2,s2,s2)
end
	
function createNoiseSnake(n)
	noiseSnakes = []
	for i in 1:n
		SE= Manifolds.SpecialEuclidean(2)
	    SO= Manifolds.SpecialOrthogonal(2)
		M = Manifolds.ProductManifold(SE,SO,SO,SO,SO)
		Id = createIdentitySnake()
		filler = getEpsilon("SE")
		s1 = createSE2(filler[1],filler[2],filler[3])
		s2 = createSO2(getEpsilon("SO")[1])
		s3 = createSO2(getEpsilon("SO")[1])
		s4 = createSO2(getEpsilon("SO")[1])
		s5 = createSO2(getEpsilon("SO")[1])
		push!(noiseSnakes,exp(M,Id,Manifolds.ProductRepr(s1,s2,s3,s4,s5)))
	end
	return noiseSnakes
end



function combine(mewSnake,noiseSnakes,n)
	snakes = []
	for i in 1:n
		snake = []
		for j in 1:5
			push!(snake,noiseSnakes[i].parts[j]*mewSnake.parts[j])
		end
		push!(snakes,Manifolds.ProductRepr(snake[1],snake[2],snake[3],snake[4],snake[5]))
	end
	return snakes
end

function createSnake(thetas,x,y,n)
	noiseSnakes = createNoiseSnake(n)
	s1 = createSE2(thetas[1],x,y)
	s2 = createSO2(thetas[2])
	s3 = createSO2(thetas[3])
	s4 = createSO2(thetas[4])
	s5 = createSO2(thetas[5])
	mewSnake = Manifolds.ProductRepr(s1,s2,s3,s4,s5)
	return combine(mewSnake,noiseSnakes,n)
end

function toMatrix(productManifold)
	matrix = 1.0*Matrix(LinearAlgebra.I, 11,11)
	matrix[(1:3),(1:3)] = productManifold.parts[1]
	matrix[(4:5),(4:5)] = productManifold.parts[2]
	matrix[(6:7),(6:7)] = productManifold.parts[3]
	matrix[(8:9),(8:9)] = productManifold.parts[4]
	matrix[(10:11),(10:11)] = productManifold.parts[5]
	return matrix
end

function toProductManifold(matrix)
	return Manifolds.ProductRepr(matrix[(1:3),(1:3)],matrix[(4:5),(4:5)],matrix[(6:7),(6:7)],matrix[(8:9),(8:9)],matrix[(10:11),(10:11)],)
end
	
function CalculateIntrinsicMean(snakes,iterations)
	SE= Manifolds.SpecialEuclidean(2)
    SO= Manifolds.SpecialOrthogonal(2)
	M = Manifolds.ProductManifold(SE,SO,SO,SO,SO)
	mew = toProductManifold(1.0*Matrix(LinearAlgebra.I, 11,11))
	identity = createIdentitySnake()
	n=length(snakes)
	for i in 1:iterations
		deltaS = inv(toMatrix(mew))*toMatrix(snakes[1])
		summation = toMatrix(ProdManifoldLog(M,toProductManifold(deltaS)))
		for j in 2:n
			deltaS = inv(toMatrix(mew))*toMatrix(snakes[j])
			summation = summation + toMatrix(ProdManifoldLog(M,toProductManifold(deltaS)))
		end
		summation = summation/n
		deltaMew = ProdManifoldExp(M,toProductManifold(summation))
		mew = toProductManifold(toMatrix(mew)*toMatrix(deltaMew))
	end
	return mew
end
	
	
end

# ╔═╡ 22ff5f42-3bb2-4a43-bd00-6ff35a27962f
begin
#PCA has 5 parts
#1)center data (distance between snake and instrinsic mean)
#2)Calculate cov matrix 
#    2.1) calculate the variance of each component: (1/n-1) sum(distance between sample component and mean for component squared)
#    2.2) calculate covariance between all components:  (1/n-1) sum( (distance between sample component A and mean for component A) * (distance between sample component B and mean for component B)
#3) find eigenVal and eigenvec
#4) order
#5) PCA
function calculateCov(x)
	SE= Manifolds.SpecialEuclidean(2)
    SO= Manifolds.SpecialOrthogonal(2)
	M = Manifolds.ProductManifold(SE,SO,SO,SO,SO)
	n_components =length(x[1].parts)+2
	distances = zeros(length(x),n_components)
	CovarianceMatrix = zeros(n_components,n_components)
	for i in 1:n_components
		for j in 1:length(x)
			if i == 1
				distances[j,i]= abs(Manifolds.log_lie(M[i],x[j].parts[i])[2,1])
			elseif i in [2,3]
				distances[j,i]= abs(Manifolds.log_lie(M[1],x[j].parts[1])[i-1,3])
			else
				distances[j,i]= abs(Manifolds.log_lie(M[i-2],x[j].parts[i-2])[2,1])
			end
		end
	end
	
	for i in 1:n_components
		for j in 1:n_components
			covariance = 0
			for k in 1:length(x)
				covariance = covariance + distances[k,i]*distances[k,j]
			end
			covariance = covariance/(length(x)-1)
			CovarianceMatrix[i,j]=covariance
		end
	end
	return CovarianceMatrix
end

function OrderEigens(U,lambda)
	orderedU = []
	orderedLambda = []
	n_components = length(lambda)
	for i in 1:n_components
		push!(orderedU,U[:,findmax(lambda)[2]])
		push!(orderedLambda,lambda[findmax(lambda)[2]])
		deleteat!(lambda,findmax(lambda)[2]:findmax(lambda)[2])
	end
	return orderedU, orderedLambda
end
	
function LiePCA(snakes,IntrinsicMean)
	SE= Manifolds.SpecialEuclidean(2)
    SO= Manifolds.SpecialOrthogonal(2)
	M = Manifolds.ProductManifold(SE,SO,SO,SO,SO)
	S = 0.0*Matrix(LinearAlgebra.I, 11,11)
	n=length(snakes)
	x = []
# 1) Center Data
#Center Data by inverse(mew)*snake
	for i in 1:n
		push!(x,toProductManifold(inv(toMatrix(IntrinsicMean))*toMatrix(snakes[i])))
	end
#Calculate Covariance Matrix
	CovarianceMatrix = calculateCov(x)
	U = LinearAlgebra.eigvecs(CovarianceMatrix)
	lambda =LinearAlgebra.eigvals(CovarianceMatrix)
	# orderedU, orderedlambda = OrderEigens(U,lambda)
	return U,lambda,CovarianceMatrix #,orderedU, orderedlambda 
end
# function plotSnake(snake)
# 	thetas= []
# 	SE= Manifolds.SpecialEuclidean(2)
#     SO= Manifolds.SpecialOrthogonal(2)
# 	M = Manifolds.ProductManifold(SE,SO,SO,SO,SO)
# 	X = []
# 	Y = []
# 	push!(X,Manifolds.log_lie(M[1],snake.parts[1])[1,3])
# 	push!(Y,Manifolds.log_lie(M[1],snake.parts[1])[2,3])
# 	currentTheta = 0
# 	for i in 1:5
# 		push!(thetas,Manifolds.log_lie(M[i],snake.parts[i])[2,1])
# 			# push!(X,X[i-1]+5*sin(thetas[i]-pi))
# 			# push!(Y,Y[i-1]+5*cos(thetas[i]-pi))
# 		push!(X,X[i]+5*sin(thetas[i]+currentTheta))
# 		push!(Y,Y[i]+5*cos(thetas[i]+currentTheta))
# 		currentTheta=thetas[i]+currentTheta
# 	end
# 	p = Plots.plot(X,Y,aspect_ratio=:equal,label="Intrinsic Mean Snake")
# 	return p
# end
	
# function plotSnake(snake)
# 	thetas= []
# 	SE= Manifolds.SpecialEuclidean(2)
#     SO= Manifolds.SpecialOrthogonal(2)
# 	M = Manifolds.ProductManifold(SE,SO,SO,SO,SO)
# 	X = []
# 	Y = []
# 	for i in 1:5
# 		push!(thetas,Manifolds.log_lie(M[i],snake.parts[i])[2,1])
# 		if i == 1
# 			push!(X,Manifolds.log_lie(M[i],snake.parts[i])[1,3])
# 			push!(Y,Manifolds.log_lie(M[i],snake.parts[i])[2,3])
# 		else
# 			push!(X,X[i-1]+5*sin(thetas[i]-pi))
# 			push!(Y,Y[i-1]+5*cos(thetas[i]-pi))
# 		end
# 	end
# 	p = Plots.plot(X,Y,aspect_ratio=:equal,label="Intrinsic Mean Snake")
# 	return p
# end
function plotSnake(snake,label)
	thetas= []
	SE= Manifolds.SpecialEuclidean(2)
    SO= Manifolds.SpecialOrthogonal(2)
	M = Manifolds.ProductManifold(SE,SO,SO,SO,SO)
	X = []
	Y = []
	for i in 1:5
		push!(thetas,Manifolds.log_lie(M[i],snake.parts[i])[2,1])
		if i == 1
			push!(X,Manifolds.log_lie(M[i],snake.parts[i])[1,3])
			push!(Y,Manifolds.log_lie(M[i],snake.parts[i])[2,3])
		else
			push!(X,X[i-1]+5*sin(thetas[i]+thetas[1]))
			push!(Y,Y[i-1]+5*cos(thetas[i]+thetas[1]))
		end
	end
	p = Plots.plot(X,Y,aspect_ratio=:equal,label=label)
	return p
end

function PCAExp(PC1)
	SE= Manifolds.SpecialEuclidean(2)
    SO= Manifolds.SpecialOrthogonal(2)
	M = Manifolds.ProductManifold(SE,SO,SO,SO,SO)
	Group = []
	for i in 1:5
		if i == 1
			C1Matrix = createSE2(PC1[1],PC1[2],PC1[3])
			push!(Group,Manifolds.exp_lie(SE,C1Matrix))
		else
			Matrix = createSO2(PC1[i+2])
			push!(Group,Manifolds.exp_lie(SO,Matrix))
		end
	end
	return Manifolds.ProductRepr(Group[1],Group[2],Group[3],Group[4],Group[5])
end
	
function allTogether(thetas,x,y,n)
	p = createSnake(thetas,x,y,n)
	intrinsicMean = CalculateIntrinsicMean(p,100)
	U,lambda,cov= LiePCA(p,intrinsicMean)
	uFull = sqrt(lambda[1])*U[:,1] +sqrt(lambda[2])*U[:,2] +sqrt(lambda[3])*U[:,3] +sqrt(lambda[4])*U[:,4] +sqrt(lambda[5])*U[:,5]
	u5 =sqrt(lambda[5])*U[:,5]
	FullPCSnake = toProductManifold(toMatrix(intrinsicMean)*toMatrix(PCAExp(uFull)))
	ReducedPCSnake =toProductManifold(toMatrix(intrinsicMean)*toMatrix(PCAExp(u5)))
	
	return U,lambda,plotSnake(intrinsicMean,"Intrinsic Mean Snake"),plotSnake(ReducedPCSnake,"Reduced Snake"),plotSnake(FullPCSnake,"Full Snake")
	# return U,lambda,X,Y
end
end

# ╔═╡ c7d79774-d721-4271-b1b5-ea47bc6aa0a8
sin(-pi)

# ╔═╡ 48c852dd-b633-4c09-aa72-6a552f589571
cos(pi)

# ╔═╡ d9322024-8122-468f-b319-284a9d5858b7
sin(-pi-2*pi)

# ╔═╡ c8924dad-8121-4893-848f-a8e2d3f34579
sin(pi)

# ╔═╡ 04ab2a93-a49f-4e91-be9f-7e439d5c161f
begin
a=Plots.Animation()
b=Plots.Animation()
c=Plots.Animation()
# Plots.@gif for i in [1,2]
#     Plots.plot(sin, 0, i * 2pi / 10)
# end
theta = -pi/3
for i in 1:6
	U,Lambda,regP,reducedP,fullP= allTogether([pi/3,-theta,theta,-theta,theta],30,20,100)
	theta = theta + 2*pi/15
    Plots.frame(a, regP)
	Plots.frame(b,reducedP)
	Plots.frame(c,fullP)
	
end
end

# ╔═╡ a8b1acbe-e6b1-4319-88da-7edc334db542
pathof(Plots)

# ╔═╡ 40a3d7bc-f862-4864-b2e4-9593d4a41e9c
b

# ╔═╡ 591e461e-173d-479a-9b91-fc3053b857a9
Plots.gif(a,fps=1)

# ╔═╡ 08419c9c-1ded-4671-84cb-e79c611c4177
Plots.gif(b,fps=1)

# ╔═╡ 7c0c84cf-055a-450d-80c0-e4cebc01a78c
Plots.gif(c,fps=1)

# ╔═╡ 1a86c737-81f5-4af9-97bc-4b0e32a4d687
c

# ╔═╡ ea40b02b-cab7-4c57-aec9-fe70b26ebb54
# begin
# # function PCAExp(PC1)
# # 	SE= Manifolds.SpecialEuclidean(2)
# #     SO= Manifolds.SpecialOrthogonal(2)
# # 	M = Manifolds.ProductManifold(SE,SO,SO,SO,SO)
# # 	Group = []
# # 	for i in 1:5
# # 		if i == 1
# # 			C1Matrix = createSE2(PC1[1],PC1[2],PC1[3])
# # 			push!(Group,Manifolds.exp_lie(SE,C1Matrix))
# # 		else
# # 			Matrix = createSO2(PC1[i+2])
# # 			push!(Group,Manifolds.exp_lie(SO,Matrix))
# # 		end
# # 	end
# # 	return Manifolds.ProductRepr(Group[1],Group[2],Group[3],Group[4],Group[5])
# # end
# end

# ╔═╡ 41613c73-6dd8-4c9c-8248-85e4cbc15774
begin
theta1 = pi/3
U,Lambda,p,p2 = allTogether([theta1,-theta1,theta1,-theta1,theta1],30,20,100)
end

# ╔═╡ fd3906cd-741f-4549-a71b-4e04bb90f1f2
Lambda

# ╔═╡ ec17392d-3822-4a9b-b4b5-fadf40d45718
# begin
# i =5 
# i in [1,2,3,4,5]
# end

# ╔═╡ 5ea2bbd4-ed74-45d2-b54e-bbbb3eafc35a
U

# ╔═╡ ce54fa38-eadb-42c4-86a3-17d156a2683d
Lambda[7]+Lambda[6]/sum(Lambda)

# ╔═╡ e0cd8266-c28d-4c52-b3c7-4f00eeb77505
# U[:,5]

# ╔═╡ 686d9dd9-86c5-4e18-9743-cf16095a6c19
# # LinearAlgebra.Transpose(Lambda)*U
# Lambda[5]

# ╔═╡ ae433651-0a12-435e-8f2e-3cf6f24600fb
# u1 = Lambda[5]*U[:,5]

# ╔═╡ 0aad227c-6a05-48cf-850f-2f18d3caf78a
# u2 = Lambda[4]*U[:,4]

# ╔═╡ a3e577ee-76f9-4447-8fc9-140434d1fa9c
# u3 = Lambda[3]*U[:,3]

# ╔═╡ f2289998-294d-429d-b495-ad7941b5e1ab
# u4 = Lambda[2]*U[:,2]

# ╔═╡ 6658c1d1-c2c2-4c90-b509-cdbef9f35417
# u5 =sqrt(Lambda[5])*U[:,5]

# ╔═╡ 74c3d4ae-6b9f-47c4-a0a3-b786f3cacc83
# u1+u2

# ╔═╡ 09d5a17b-46e8-41cf-8417-652b6dec6c98
# cov

# ╔═╡ 6d136817-0a5c-4103-a9d9-a65f3b92db89
# LinearAlgebra.cross(Lambda,U)

# ╔═╡ 74b41511-cd14-4a1a-8144-84a92299b081
# tranposed = LinearAlgebra.Transpose(Lambda)

# ╔═╡ 8c75e3ac-316f-4ca2-9864-92adb71f8d2b
# U*Lambda

# ╔═╡ 5015763d-6e2d-42c9-a302-72ad75e2e0b5
# mu

# ╔═╡ ef29b250-cf46-40f2-b668-9c59356c10b1
# u6 = u5+u4+u3+u2+u1

# ╔═╡ 71a63b54-a409-460a-aab0-b6e5be3c8589
# plotSnake(mu)

# ╔═╡ e018ff9c-f0ce-432d-a04d-c8ccfab1fbcf
# PCSnake =toProductManifold(toMatrix(mu)*toMatrix(PCAExp(u5)))

# ╔═╡ 879d4039-2e70-4e17-a26c-38054e22101b
# plotSnake(PCSnake)

# ╔═╡ 22d42d24-2de2-4b2c-815b-0a3e2bf45d4a
# begin
# a=Plots.Animation()
# theta = -pi
# for i in 1:11
# 	U,Lambda,p= allTogether([theta,-theta,theta,-theta,theta],30,20,100)
# 	theta = theta + 2*pi/10
#     Plots.frame(a, p)
# end
# end

# ╔═╡ 053260f6-521f-441f-bcda-f38626e3649a
# begin
# a=Plots.Animation()
# b=Plots.Animation()
# # Plots.@gif for i in [1,2]
# #     Plots.plot(sin, 0, i * 2pi / 10)
# # end
# theta = -pi/3
# for i in 1:6
# 	U,Lambda,regP,pcaP= allTogether([theta,-theta,theta,-theta,theta],30,20,100)
# 	theta = theta + 2*pi/15
#     Plots.frame(a, regP)
# 	Plots.frame(b,pcaP)
	
# end
# end

# ╔═╡ 6f4b077b-f3ef-4468-83bf-8643b8f7e7e4
# Plots.gif(a,fps=1)

# ╔═╡ 7a84ab58-a0d0-4fc4-8b87-d7461205920b
# U,Lambda = allTogether([pi/4,-pi/4,pi/4,-pi/4,pi/4],30,20,1000)

# ╔═╡ d4d3cc84-86ee-4e7d-af4f-dbea1c010775
# U

# ╔═╡ 7c11788d-a58e-4a49-9a74-0570e89cc0de
# Lambda

# ╔═╡ 38f42070-4811-42f9-bebb-139521578dd5
# U2,Lambda2 = allTogether([0,0,0,0,0],0,0,1000)

# ╔═╡ cb6651a0-7bce-46b8-9eb0-2c36a8018ccc
# U2

# ╔═╡ 1c04caed-db65-4619-9122-ab72971d01c5
# Lambda2

# ╔═╡ 0fa0e434-085c-4961-a2e3-652beaf5ac06


# ╔═╡ 528914e3-0fb1-4a43-a321-c209721ccede
# begin
# 	thetas = [0,0,0,0,0]
# 	x=30
# 	y=20
# 	n = 100
# 	p = createSnake(thetas,x,y,n)
# 	IntrinsicMean = CalculateIntrinsicMean(p,100)
# 	# U = LiePCA(p,IntrinsicMean)
# 	# U
# 	U,lambda,newU,newLambda = LiePCA(p,IntrinsicMean)
# 	U
# end

# ╔═╡ b0fcc163-37e7-4ad8-950d-713ce6afa874
# lambda

# ╔═╡ 4643f16b-d3e8-4ec8-8599-4f4664f33eb7
# newU

# ╔═╡ 083b3ff5-8d9d-46a5-909d-64174cf6ac2b
# newLambda

# ╔═╡ 09197117-175f-4d0a-8513-418e4a2bd44f
#begin
# 	thetas = [0,0,0,0,0]
# 	x=30
# 	y=20
# 	n = 100
# 	p = createSnake(thetas,x,y,n)
# 	IntrinsicMean = CalculateIntrinsicMean(p,100)
# 	# U = LiePCA(p,IntrinsicMean)
# 	# U
# 	U,lambda,newU,newLambda = LiePCA(p,IntrinsicMean)
# 	U
# end

# ╔═╡ 01619322-e84d-464f-8d19-6e4bae0061b5
# begin
# 	thetas = [pi/4,-pi/4,pi/4,-pi/4,pi/4]
# 	x=30
# 	y=20
# 	n = 100
# 	p = createSnake(thetas,x,y,n)
# 	IntrinsicMean = CalculateIntrinsicMean(p,10)
# 	# U = LiePCA(p,IntrinsicMean)
# 	# U
# 	LiePCA(p,IntrinsicMean)
# end

# ╔═╡ ad1791b1-a4dc-49d6-8add-1432071360b3
# begin
# a=Plots.Animation()
# # Plots.@gif for i in [1,2]
# #     Plots.plot(sin, 0, i * 2pi / 10)
# # end
# for i in 1:10
#     plt = Plots.bar(1:i, ylim=(0,10), xlim=(0,10), lab="")
#     Plots.frame(a, plt)
# end
# end

# ╔═╡ 20ea08df-e39d-415e-a00d-d7e2a0a1b251
# begin
# import Images

# end

# ╔═╡ e64b4f76-5b87-4897-a794-8360226abdda
# a.dir*"/"*a.frames[1]

# ╔═╡ e6bb27b6-1b5f-4d59-bf84-58389d8b9b3e
# -pi

# ╔═╡ e548e4cd-8d16-46c6-b442-af9631d4b99e
# begin
# thetas = -1*pi
# print(thetas)
# print("\n")
# for i in 1:11
# 	print(thetas)
# 	print("\n")
# 	thetas = thetas + 2*pi/10
# end
# end

# ╔═╡ ff01e3e9-238f-4e33-a136-1dc43e722759
# Images.load(a.dir*"/"*a.frames[1])

# ╔═╡ 682e10aa-4109-4b24-b4d6-81adb7129c60
# Images.load(a.dir*"/"*a.frames[2])

# ╔═╡ e16184e2-80dc-4175-93a3-8af7ae2adb41
# Images.load(a.dir*"/"*a.frames[3])

# ╔═╡ 4fdda677-11fa-4d01-b90a-c64e48c0bcb4
# Images.load(a.dir*"/"*a.frames[4])

# ╔═╡ aed60318-2fb2-4c5c-9504-e575f3509847
# Images.load(a.dir*"/"*a.frames[5])

# ╔═╡ 5952b7c7-6d87-458b-b7c0-e26b2d7fbbd6
# Images.load(a.dir*"/"*a.frames[6])

# ╔═╡ f26acd44-5f5c-4688-939c-a4db8c91595b
# Images.load(a.dir*"/"*a.frames[7])

# ╔═╡ 4f88bb3b-de79-4bd4-ab8e-9e5f68cf8cb7
# Images.load(a.dir*"/"*a.frames[8])

# ╔═╡ ccb44d88-1f4c-441a-830c-c8b1e7f9150b
# Images.load(a.dir*"/"*a.frames[9])

# ╔═╡ dbd7edf6-2aa6-4386-ad0a-7917dcbbd519
# Images.load(a.dir*"/"*a.frames[10])

# ╔═╡ 4ef64355-19cb-4b5b-9c13-f066dc4351f0
# Images.load(a.dir*"/"*a.frames[11])

# ╔═╡ 92211e50-b15e-429d-a330-6303219aeda8
# IntrinsicMean

# ╔═╡ b624efc3-f384-41a9-9df6-022e8fe58b05
# begin
# SE= Manifolds.SpecialEuclidean(2)
# SO= Manifolds.SpecialOrthogonal(2)
# M = Manifolds.ProductManifold(SE,SO,SO,SO,SO)
# logging = ProdManifoldLog(M,toProductManifold(inv(toMatrix(IntrinsicMean))*toMatrix(p[1])))
# LinearAlgebra.norm(logging.parts[1])
# end

# ╔═╡ 9ed4ad8c-5506-4163-82e4-4216d615ad85
# inv(toMatrix(IntrinsicMean))

# ╔═╡ c9e2aede-26c4-4d6f-acbc-102ca855eab7
# toMatrix(p[1])

# ╔═╡ 8a4f31e7-5e35-4cf4-9926-49db20ed67ab
# inv(toMatrix(IntrinsicMean))*toMatrix(p[1])

# ╔═╡ aa3e96fb-a453-4a51-b0a1-5c0ffb7e0f28
# begin
# Manifolds.log_lie(SE,IntrinsicMean.parts[1])
# end

# ╔═╡ d5f01148-d81e-4d98-a24c-9224d9a7a5d5
# begin
# Manifolds.log_lie(SE,p[1].parts[1])
# end

# ╔═╡ 951346fa-703c-4652-b85f-7161fa61f2bd
# Manifolds.log_lie(SE,p[1].parts[1]) - Manifolds.log_lie(SE,IntrinsicMean.parts[1])

# ╔═╡ 0ed0c873-4567-4d2e-a748-bce3d2dbf08a
# begin
# Manifolds.exp_lie(SE,Manifolds.log_lie(SE,p[1].parts[1]) - Manifolds.log_lie(SE,IntrinsicMean.parts[1]))
# end

# ╔═╡ a9ff4ac2-4021-4a5d-a639-0eaa53758a23
# IntrinsicMean

# ╔═╡ 8b7acec9-8042-4417-a27b-9f8b058a0b34
# p[1]

# ╔═╡ 45c4e39c-db77-413c-a77e-6dcdc484ce63
# begin
# SE= Manifolds.SpecialEuclidean(2)
# Manifolds.log_lie(SE,IntrinsicMean.parts[1])
# end

# ╔═╡ be4b3c8f-a8a7-4d94-9a20-ac577b60a635
# begin
# Manifolds.log_lie(SE,p[1].parts[1])
# end

# ╔═╡ ba9ed636-a6c0-4a4c-b961-8e2a4d9463b5
# distance = toProductManifold(inv(toMatrix(IntrinsicMean))*toMatrix(p[1]))

# ╔═╡ cc250424-e032-4740-9ed5-7267d143aaf3
# begin
# ahhhh = Manifolds.log_lie(SE,distance.parts[1])
# end

# ╔═╡ bad443b3-f94e-46d3-bae7-72da23bb7a11
# begin
# IMustbeDumb = [ahhhh[2,1],ahhhh[1,3],ahhhh[2,3]]
# LinearAlgebra.norm(IMustbeDumb)
# end

# ╔═╡ 12f70b6d-0dd5-4516-b58d-f2d77606fc20
# LinearAlgebra.eigvecs(U)

# ╔═╡ 5e39f082-3ac9-453d-add0-03ff68cc7615
# begin
# LinearAlgebra.eigvecs(U[1:2,1:2])
# # U[1:3,1:3]
# # U[1:3,1:3]*transpose(U[1:3,1:3])
# end

# ╔═╡ 08ea2dbc-119b-457a-a7a3-8c7c76e65885
# allTogetherS([pi/4,-pi/4,pi/4,-pi/4,pi/4],30,20,1000)

# ╔═╡ e161fe96-b2b9-4068-8f2a-fc1925196955
# begin
# 	allTogether([0,0,0,0,0],0,0,1000)
# end

# ╔═╡ 9d24db4e-c84f-4fa2-b027-b64f77e874b0
# allTogether([0,0,0,0,0],30,20,1000)

# ╔═╡ 0ba93020-04f2-4d20-8882-34f7392e291e
# allTogether([pi/4,-pi/4,pi/4,-pi/4,pi/4],30,20,1000)

# ╔═╡ 7e309e52-87f0-4dab-9e38-af5a166e65e7
# allTogether([pi/4,pi/4,-pi/4,-pi/4,-pi/4],30,20,1000)

# ╔═╡ 47feff1f-f796-496b-a0ee-a7482faf139c
# begin
# 	thetas = [pi/4,-pi/4,pi/4,-pi/4,pi/4]
# 	x=30
# 	y=20
# 	n = 10
# 	p = createSnake(thetas,x,y,n)
# 	IntrinsicMean = CalculateIntrinsicMean(p,10)
# 	U,lambda,S = LiePCA(p,IntrinsicMean)
# 	U
# end

# ╔═╡ 39449216-e0b5-4f69-9548-5c99e65edd17
U

# ╔═╡ 8dd4e313-e0a4-408d-abc9-0831a67e0845
# begin
# 	A = zeros(11,11)
# 	for i in 1:11
# 		A = A +lambda[i]*(U[:,i]*transpose(U[:,i]))
# 	end
# 	A
# end

# ╔═╡ 88679086-b52c-4a5c-88fe-6db62c8254b6
# begin
# SE= Manifolds.SpecialEuclidean(2)
# SO= Manifolds.SpecialOrthogonal(2)
# M = Manifolds.ProductManifold(SE,SO,SO,SO,SO)
# U*ones(11,1)
# end

# ╔═╡ 26b2be57-72b1-474c-9b77-46338c438665
# begin
# LinearAlgebra.eigvecs(S)
# end

# ╔═╡ 1541b449-c5ff-4771-9bdf-5c05f82c3bf5
# LinearAlgebra.eigvals(S)

# ╔═╡ 84621943-c11c-415c-b049-62415e9995d4
# begin
# 	# thetas = [pi/4,-pi/4,pi/4,-pi/4,pi/4]
# 	thetas = [0,0,0,0,0]
# 	# thetas2 = [0.750878,0,0,0,0]
# 	# x2 = 3.84679
# 	# y2 =  -1.70228
# 	x=30
# 	y=20
# 	# snakes = []
# 	# for i in 1:5
# 	#  push!(snakes,createSnake(thetas,x,y,10))
# 	# end
# 	n = 100
# 	p = createSnake(thetas,x,y,n)
# 	intrinsicMean = CalculateIntrinsicMean(p,1000)
# 	# sum = zeros(3,3)
# 	# transformed = []
# 	# for i in 1:n
# 	# 	sum = sum + p[i].parts[1]
# 	# 	push!(transformed,p[i].parts[1])
# 	# end
# 	# sum/n
# end

# ╔═╡ 3f68ea76-407d-4104-a9de-353fe3deed79
# CalculatedIntrinsicMean(transformed, 1)

# ╔═╡ 00000000-0000-0000-0000-000000000001
PLUTO_PROJECT_TOML_CONTENTS = """
[deps]
Distributions = "31c24e10-a181-5473-b8eb-7969acd0382f"
Graphs = "86223c79-3864-5bf0-83f7-82e725a168b6"
LinearAlgebra = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"
Manifolds = "1cead3c2-87b3-11e9-0ccd-23c62b72b94e"
ManifoldsBase = "3362f125-f0bb-47a3-aa74-596ffd7ef2fb"
Plots = "91a5bcdd-55d7-5caf-9e0b-520d859cae80"
Random = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"

[compat]
Distributions = "~0.25.76"
Graphs = "~1.7.4"
Manifolds = "~0.8.35"
ManifoldsBase = "~0.13.22"
Plots = "~1.35.5"
"""

# ╔═╡ 00000000-0000-0000-0000-000000000002
PLUTO_MANIFEST_TOML_CONTENTS = """
# This file is machine-generated - editing it directly is not advised

[[AbstractFFTs]]
deps = ["ChainRulesCore", "LinearAlgebra"]
git-tree-sha1 = "69f7020bd72f069c219b5e8c236c1fa90d2cb409"
uuid = "621f4979-c628-5d54-868e-fcf4e3e8185c"
version = "1.2.1"

[[Adapt]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "195c5505521008abea5aee4f96930717958eac6f"
uuid = "79e6a3ab-5dfb-504d-930d-738a2a938a0e"
version = "3.4.0"

[[ArgTools]]
uuid = "0dad84c5-d112-42e6-8d28-ef12dabb789f"

[[ArnoldiMethod]]
deps = ["LinearAlgebra", "Random", "StaticArrays"]
git-tree-sha1 = "62e51b39331de8911e4a7ff6f5aaf38a5f4cc0ae"
uuid = "ec485272-7323-5ecc-a04f-4719b315124d"
version = "0.2.0"

[[ArrayInterfaceCore]]
deps = ["LinearAlgebra", "SparseArrays", "SuiteSparse"]
git-tree-sha1 = "e6cba4aadba7e8a7574ab2ba2fcfb307b4c4b02a"
uuid = "30b0a656-2188-435a-8636-2ec0e6a096e2"
version = "0.1.23"

[[ArrayInterfaceStaticArraysCore]]
deps = ["Adapt", "ArrayInterfaceCore", "LinearAlgebra", "StaticArraysCore"]
git-tree-sha1 = "93c8ba53d8d26e124a5a8d4ec914c3a16e6a0970"
uuid = "dd5226c6-a4d4-4bc7-8575-46859f9c95b9"
version = "0.1.3"

[[Artifacts]]
uuid = "56f22d72-fd6d-98f1-02f0-08ddc0907c33"

[[Base64]]
uuid = "2a0f44e3-6c83-55bd-87e4-b1978d98bd5f"

[[BitFlags]]
git-tree-sha1 = "84259bb6172806304b9101094a7cc4bc6f56dbc6"
uuid = "d1d4a3ce-64b1-5f1a-9ba4-7e7e69966f35"
version = "0.1.5"

[[Bzip2_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "19a35467a82e236ff51bc17a3a44b69ef35185a2"
uuid = "6e34b625-4abd-537c-b88f-471c36dfa7a0"
version = "1.0.8+0"

[[Cairo_jll]]
deps = ["Artifacts", "Bzip2_jll", "Fontconfig_jll", "FreeType2_jll", "Glib_jll", "JLLWrappers", "LZO_jll", "Libdl", "Pixman_jll", "Pkg", "Xorg_libXext_jll", "Xorg_libXrender_jll", "Zlib_jll", "libpng_jll"]
git-tree-sha1 = "4b859a208b2397a7a623a03449e4636bdb17bcf2"
uuid = "83423d85-b0ee-5818-9007-b63ccbeb887a"
version = "1.16.1+1"

[[Calculus]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "f641eb0a4f00c343bbc32346e1217b86f3ce9dad"
uuid = "49dc2e85-a5d0-5ad3-a950-438e2897f1b9"
version = "0.5.1"

[[ChainRulesCore]]
deps = ["Compat", "LinearAlgebra", "SparseArrays"]
git-tree-sha1 = "e7ff6cadf743c098e08fca25c91103ee4303c9bb"
uuid = "d360d2e6-b24c-11e9-a2a3-2a2ae2dbcce4"
version = "1.15.6"

[[ChangesOfVariables]]
deps = ["ChainRulesCore", "LinearAlgebra", "Test"]
git-tree-sha1 = "38f7a08f19d8810338d4f5085211c7dfa5d5bdd8"
uuid = "9e997f8a-9a97-42d5-a9f1-ce6bfc15e2c0"
version = "0.1.4"

[[CodecZlib]]
deps = ["TranscodingStreams", "Zlib_jll"]
git-tree-sha1 = "ded953804d019afa9a3f98981d99b33e3db7b6da"
uuid = "944b1d66-785c-5afd-91f1-9de20f533193"
version = "0.7.0"

[[ColorSchemes]]
deps = ["ColorTypes", "ColorVectorSpace", "Colors", "FixedPointNumbers", "Random"]
git-tree-sha1 = "1fd869cc3875b57347f7027521f561cf46d1fcd8"
uuid = "35d6a980-a343-548e-a6ea-1d62b119f2f4"
version = "3.19.0"

[[ColorTypes]]
deps = ["FixedPointNumbers", "Random"]
git-tree-sha1 = "eb7f0f8307f71fac7c606984ea5fb2817275d6e4"
uuid = "3da002f7-5984-5a60-b8a6-cbb66c0b333f"
version = "0.11.4"

[[ColorVectorSpace]]
deps = ["ColorTypes", "FixedPointNumbers", "LinearAlgebra", "SpecialFunctions", "Statistics", "TensorCore"]
git-tree-sha1 = "d08c20eef1f2cbc6e60fd3612ac4340b89fea322"
uuid = "c3611d14-8923-5661-9e6a-0046d554d3a4"
version = "0.9.9"

[[Colors]]
deps = ["ColorTypes", "FixedPointNumbers", "Reexport"]
git-tree-sha1 = "417b0ed7b8b838aa6ca0a87aadf1bb9eb111ce40"
uuid = "5ae59095-9a9b-59fe-a467-6f913c188581"
version = "0.12.8"

[[Compat]]
deps = ["Dates", "LinearAlgebra", "UUIDs"]
git-tree-sha1 = "3ca828fe1b75fa84b021a7860bd039eaea84d2f2"
uuid = "34da2185-b29b-5c13-b0c7-acf172513d20"
version = "4.3.0"

[[CompilerSupportLibraries_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "e66e0078-7015-5450-92f7-15fbd957f2ae"

[[Contour]]
git-tree-sha1 = "d05d9e7b7aedff4e5b51a029dced05cfb6125781"
uuid = "d38c429a-6771-53c6-b99e-75d170b6e991"
version = "0.6.2"

[[CovarianceEstimation]]
deps = ["LinearAlgebra", "Statistics", "StatsBase"]
git-tree-sha1 = "3c8de95b4e932d76ec8960e12d681eba580e9674"
uuid = "587fd27a-f159-11e8-2dae-1979310e6154"
version = "0.2.8"

[[DataAPI]]
git-tree-sha1 = "46d2680e618f8abd007bce0c3026cb0c4a8f2032"
uuid = "9a962f9c-6df0-11e9-0e5d-c546b8b5ee8a"
version = "1.12.0"

[[DataStructures]]
deps = ["Compat", "InteractiveUtils", "OrderedCollections"]
git-tree-sha1 = "d1fff3a548102f48987a52a2e0d114fa97d730f0"
uuid = "864edb3b-99cc-5e75-8d2d-829cb0a9cfe8"
version = "0.18.13"

[[DataValueInterfaces]]
git-tree-sha1 = "bfc1187b79289637fa0ef6d4436ebdfe6905cbd6"
uuid = "e2d170a0-9d28-54be-80f0-106bbe20a464"
version = "1.0.0"

[[Dates]]
deps = ["Printf"]
uuid = "ade2ca70-3891-5945-98fb-dc099432e06a"

[[DelimitedFiles]]
deps = ["Mmap"]
uuid = "8bb1440f-4735-579b-a4ab-409b98df4dab"

[[DensityInterface]]
deps = ["InverseFunctions", "Test"]
git-tree-sha1 = "80c3e8639e3353e5d2912fb3a1916b8455e2494b"
uuid = "b429d917-457f-4dbc-8f4c-0cc954292b1d"
version = "0.4.0"

[[Distributed]]
deps = ["Random", "Serialization", "Sockets"]
uuid = "8ba89e20-285c-5b6f-9357-94700520ee1b"

[[Distributions]]
deps = ["ChainRulesCore", "DensityInterface", "FillArrays", "LinearAlgebra", "PDMats", "Printf", "QuadGK", "Random", "SparseArrays", "SpecialFunctions", "Statistics", "StatsBase", "StatsFuns", "Test"]
git-tree-sha1 = "04db820ebcfc1e053bd8cbb8d8bccf0ff3ead3f7"
uuid = "31c24e10-a181-5473-b8eb-7969acd0382f"
version = "0.25.76"

[[DocStringExtensions]]
deps = ["LibGit2"]
git-tree-sha1 = "c36550cb29cbe373e95b3f40486b9a4148f89ffd"
uuid = "ffbed154-4ef7-542d-bbb7-c09d3a79fcae"
version = "0.9.2"

[[Downloads]]
deps = ["ArgTools", "LibCURL", "NetworkOptions"]
uuid = "f43a241f-c20a-4ad4-852c-f6b1247861c6"

[[DualNumbers]]
deps = ["Calculus", "NaNMath", "SpecialFunctions"]
git-tree-sha1 = "5837a837389fccf076445fce071c8ddaea35a566"
uuid = "fa6b7ba4-c1ee-5f82-b5fc-ecf0adba8f74"
version = "0.6.8"

[[Einsum]]
deps = ["Compat"]
git-tree-sha1 = "4a6b3eee0161c89700b6c1949feae8b851da5494"
uuid = "b7d42ee7-0b51-5a75-98ca-779d3107e4c0"
version = "0.4.1"

[[Expat_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "bad72f730e9e91c08d9427d5e8db95478a3c323d"
uuid = "2e619515-83b5-522b-bb60-26c02a35a201"
version = "2.4.8+0"

[[FFMPEG]]
deps = ["FFMPEG_jll"]
git-tree-sha1 = "b57e3acbe22f8484b4b5ff66a7499717fe1a9cc8"
uuid = "c87230d0-a227-11e9-1b43-d7ebe4e7570a"
version = "0.4.1"

[[FFMPEG_jll]]
deps = ["Artifacts", "Bzip2_jll", "FreeType2_jll", "FriBidi_jll", "JLLWrappers", "LAME_jll", "Libdl", "Ogg_jll", "OpenSSL_jll", "Opus_jll", "PCRE2_jll", "Pkg", "Zlib_jll", "libaom_jll", "libass_jll", "libfdk_aac_jll", "libvorbis_jll", "x264_jll", "x265_jll"]
git-tree-sha1 = "74faea50c1d007c85837327f6775bea60b5492dd"
uuid = "b22a6f82-2f65-5046-a5b2-351ab43fb4e5"
version = "4.4.2+2"

[[FillArrays]]
deps = ["LinearAlgebra", "Random", "SparseArrays", "Statistics"]
git-tree-sha1 = "802bfc139833d2ba893dd9e62ba1767c88d708ae"
uuid = "1a297f60-69ca-5386-bcde-b61e274b549b"
version = "0.13.5"

[[FixedPointNumbers]]
deps = ["Statistics"]
git-tree-sha1 = "335bfdceacc84c5cdf16aadc768aa5ddfc5383cc"
uuid = "53c48c17-4a7d-5ca2-90c5-79b7896eea93"
version = "0.8.4"

[[Fontconfig_jll]]
deps = ["Artifacts", "Bzip2_jll", "Expat_jll", "FreeType2_jll", "JLLWrappers", "Libdl", "Libuuid_jll", "Pkg", "Zlib_jll"]
git-tree-sha1 = "21efd19106a55620a188615da6d3d06cd7f6ee03"
uuid = "a3f928ae-7b40-5064-980b-68af3947d34b"
version = "2.13.93+0"

[[Formatting]]
deps = ["Printf"]
git-tree-sha1 = "8339d61043228fdd3eb658d86c926cb282ae72a8"
uuid = "59287772-0a20-5a39-b81b-1366585eb4c0"
version = "0.4.2"

[[FreeType2_jll]]
deps = ["Artifacts", "Bzip2_jll", "JLLWrappers", "Libdl", "Pkg", "Zlib_jll"]
git-tree-sha1 = "87eb71354d8ec1a96d4a7636bd57a7347dde3ef9"
uuid = "d7e528f0-a631-5988-bf34-fe36492bcfd7"
version = "2.10.4+0"

[[FriBidi_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "aa31987c2ba8704e23c6c8ba8a4f769d5d7e4f91"
uuid = "559328eb-81f9-559d-9380-de523a88c83c"
version = "1.0.10+0"

[[GLFW_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Libglvnd_jll", "Pkg", "Xorg_libXcursor_jll", "Xorg_libXi_jll", "Xorg_libXinerama_jll", "Xorg_libXrandr_jll"]
git-tree-sha1 = "d972031d28c8c8d9d7b41a536ad7bb0c2579caca"
uuid = "0656b61e-2033-5cc2-a64a-77c0f6c09b89"
version = "3.3.8+0"

[[GPUArraysCore]]
deps = ["Adapt"]
git-tree-sha1 = "6872f5ec8fd1a38880f027a26739d42dcda6691f"
uuid = "46192b85-c4d5-4398-a991-12ede77f4527"
version = "0.1.2"

[[GR]]
deps = ["Base64", "DelimitedFiles", "GR_jll", "HTTP", "JSON", "Libdl", "LinearAlgebra", "Pkg", "Preferences", "Printf", "Random", "Serialization", "Sockets", "Test", "UUIDs"]
git-tree-sha1 = "00a9d4abadc05b9476e937a5557fcce476b9e547"
uuid = "28b8d3ca-fb5f-59d9-8090-bfdbd6d07a71"
version = "0.69.5"

[[GR_jll]]
deps = ["Artifacts", "Bzip2_jll", "Cairo_jll", "FFMPEG_jll", "Fontconfig_jll", "GLFW_jll", "JLLWrappers", "JpegTurbo_jll", "Libdl", "Libtiff_jll", "Pixman_jll", "Pkg", "Qt5Base_jll", "Zlib_jll", "libpng_jll"]
git-tree-sha1 = "bc9f7725571ddb4ab2c4bc74fa397c1c5ad08943"
uuid = "d2c73de3-f751-5644-a686-071e5b155ba9"
version = "0.69.1+0"

[[Gettext_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "Libiconv_jll", "Pkg", "XML2_jll"]
git-tree-sha1 = "9b02998aba7bf074d14de89f9d37ca24a1a0b046"
uuid = "78b55507-aeef-58d4-861c-77aaff3498b1"
version = "0.21.0+0"

[[Glib_jll]]
deps = ["Artifacts", "Gettext_jll", "JLLWrappers", "Libdl", "Libffi_jll", "Libiconv_jll", "Libmount_jll", "PCRE2_jll", "Pkg", "Zlib_jll"]
git-tree-sha1 = "fb83fbe02fe57f2c068013aa94bcdf6760d3a7a7"
uuid = "7746bdde-850d-59dc-9ae8-88ece973131d"
version = "2.74.0+1"

[[Graphite2_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "344bf40dcab1073aca04aa0df4fb092f920e4011"
uuid = "3b182d85-2403-5c21-9c21-1e1f0cc25472"
version = "1.3.14+0"

[[Graphs]]
deps = ["ArnoldiMethod", "Compat", "DataStructures", "Distributed", "Inflate", "LinearAlgebra", "Random", "SharedArrays", "SimpleTraits", "SparseArrays", "Statistics"]
git-tree-sha1 = "ba2d094a88b6b287bd25cfa86f301e7693ffae2f"
uuid = "86223c79-3864-5bf0-83f7-82e725a168b6"
version = "1.7.4"

[[Grisu]]
git-tree-sha1 = "53bb909d1151e57e2484c3d1b53e19552b887fb2"
uuid = "42e2da0e-8278-4e71-bc24-59509adca0fe"
version = "1.0.2"

[[HTTP]]
deps = ["Base64", "CodecZlib", "Dates", "IniFile", "Logging", "LoggingExtras", "MbedTLS", "NetworkOptions", "OpenSSL", "Random", "SimpleBufferStream", "Sockets", "URIs", "UUIDs"]
git-tree-sha1 = "a97d47758e933cd5fe5ea181d178936a9fc60427"
uuid = "cd3eb016-35fb-5094-929b-558a96fad6f3"
version = "1.5.1"

[[HarfBuzz_jll]]
deps = ["Artifacts", "Cairo_jll", "Fontconfig_jll", "FreeType2_jll", "Glib_jll", "Graphite2_jll", "JLLWrappers", "Libdl", "Libffi_jll", "Pkg"]
git-tree-sha1 = "129acf094d168394e80ee1dc4bc06ec835e510a3"
uuid = "2e76f6c2-a576-52d4-95c1-20adfe4de566"
version = "2.8.1+1"

[[HybridArrays]]
deps = ["LinearAlgebra", "Requires", "StaticArrays"]
git-tree-sha1 = "0de633a951f8b5bd32febc373588517aa9f2f482"
uuid = "1baab800-613f-4b0a-84e4-9cd3431bfbb9"
version = "0.4.13"

[[HypergeometricFunctions]]
deps = ["DualNumbers", "LinearAlgebra", "OpenLibm_jll", "SpecialFunctions", "Test"]
git-tree-sha1 = "709d864e3ed6e3545230601f94e11ebc65994641"
uuid = "34004b35-14d8-5ef3-9330-4cdb6864b03a"
version = "0.3.11"

[[Inflate]]
git-tree-sha1 = "5cd07aab533df5170988219191dfad0519391428"
uuid = "d25df0c9-e2be-5dd7-82c8-3ad0b3e990b9"
version = "0.1.3"

[[IniFile]]
git-tree-sha1 = "f550e6e32074c939295eb5ea6de31849ac2c9625"
uuid = "83e8ac13-25f8-5344-8a64-a9f2b223428f"
version = "0.5.1"

[[InteractiveUtils]]
deps = ["Markdown"]
uuid = "b77e0a4c-d291-57a0-90e8-8db25a27a240"

[[InverseFunctions]]
deps = ["Test"]
git-tree-sha1 = "49510dfcb407e572524ba94aeae2fced1f3feb0f"
uuid = "3587e190-3f89-42d0-90ee-14403ec27112"
version = "0.1.8"

[[IrrationalConstants]]
git-tree-sha1 = "7fd44fd4ff43fc60815f8e764c0f352b83c49151"
uuid = "92d709cd-6900-40b7-9082-c6be49f344b6"
version = "0.1.1"

[[IteratorInterfaceExtensions]]
git-tree-sha1 = "a3f24677c21f5bbe9d2a714f95dcd58337fb2856"
uuid = "82899510-4779-5014-852e-03e436cf321d"
version = "1.0.0"

[[JLFzf]]
deps = ["Pipe", "REPL", "Random", "fzf_jll"]
git-tree-sha1 = "f377670cda23b6b7c1c0b3893e37451c5c1a2185"
uuid = "1019f520-868f-41f5-a6de-eb00f4b6a39c"
version = "0.1.5"

[[JLLWrappers]]
deps = ["Preferences"]
git-tree-sha1 = "abc9885a7ca2052a736a600f7fa66209f96506e1"
uuid = "692b3bcd-3c85-4b1f-b108-f13ce0eb3210"
version = "1.4.1"

[[JSON]]
deps = ["Dates", "Mmap", "Parsers", "Unicode"]
git-tree-sha1 = "3c837543ddb02250ef42f4738347454f95079d4e"
uuid = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
version = "0.21.3"

[[JpegTurbo_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "b53380851c6e6664204efb2e62cd24fa5c47e4ba"
uuid = "aacddb02-875f-59d6-b918-886e6ef4fbf8"
version = "2.1.2+0"

[[Kronecker]]
deps = ["LinearAlgebra", "NamedDims", "SparseArrays", "StatsBase"]
git-tree-sha1 = "78d9909daf659c901ae6c7b9de7861ba45a743f4"
uuid = "2c470bb0-bcc8-11e8-3dad-c9649493f05e"
version = "0.5.3"

[[LAME_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "f6250b16881adf048549549fba48b1161acdac8c"
uuid = "c1c5ebd0-6772-5130-a774-d5fcae4a789d"
version = "3.100.1+0"

[[LERC_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "bf36f528eec6634efc60d7ec062008f171071434"
uuid = "88015f11-f218-50d7-93a8-a6af411a945d"
version = "3.0.0+1"

[[LZO_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "e5b909bcf985c5e2605737d2ce278ed791b89be6"
uuid = "dd4b983a-f0e5-5f8d-a1b7-129d4a5fb1ac"
version = "2.10.1+0"

[[LaTeXStrings]]
git-tree-sha1 = "f2355693d6778a178ade15952b7ac47a4ff97996"
uuid = "b964fa9f-0449-5b57-a5c2-d3ea65f4040f"
version = "1.3.0"

[[Latexify]]
deps = ["Formatting", "InteractiveUtils", "LaTeXStrings", "MacroTools", "Markdown", "OrderedCollections", "Printf", "Requires"]
git-tree-sha1 = "ab9aa169d2160129beb241cb2750ca499b4e90e9"
uuid = "23fbe1c1-3f47-55db-b15f-69d7ec21a316"
version = "0.15.17"

[[LibCURL]]
deps = ["LibCURL_jll", "MozillaCACerts_jll"]
uuid = "b27032c2-a3e7-50c8-80cd-2d36dbcbfd21"

[[LibCURL_jll]]
deps = ["Artifacts", "LibSSH2_jll", "Libdl", "MbedTLS_jll", "Zlib_jll", "nghttp2_jll"]
uuid = "deac9b47-8bc7-5906-a0fe-35ac56dc84c0"

[[LibGit2]]
deps = ["Base64", "NetworkOptions", "Printf", "SHA"]
uuid = "76f85450-5226-5b5a-8eaa-529ad045b433"

[[LibSSH2_jll]]
deps = ["Artifacts", "Libdl", "MbedTLS_jll"]
uuid = "29816b5a-b9ab-546f-933c-edad1886dfa8"

[[Libdl]]
uuid = "8f399da3-3557-5675-b5ff-fb832c97cbdb"

[[Libffi_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "0b4a5d71f3e5200a7dff793393e09dfc2d874290"
uuid = "e9f186c6-92d2-5b65-8a66-fee21dc1b490"
version = "3.2.2+1"

[[Libgcrypt_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Libgpg_error_jll", "Pkg"]
git-tree-sha1 = "64613c82a59c120435c067c2b809fc61cf5166ae"
uuid = "d4300ac3-e22c-5743-9152-c294e39db1e4"
version = "1.8.7+0"

[[Libglvnd_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libX11_jll", "Xorg_libXext_jll"]
git-tree-sha1 = "7739f837d6447403596a75d19ed01fd08d6f56bf"
uuid = "7e76a0d4-f3c7-5321-8279-8d96eeed0f29"
version = "1.3.0+3"

[[Libgpg_error_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "c333716e46366857753e273ce6a69ee0945a6db9"
uuid = "7add5ba3-2f88-524e-9cd5-f83b8a55f7b8"
version = "1.42.0+0"

[[Libiconv_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "42b62845d70a619f063a7da093d995ec8e15e778"
uuid = "94ce4f54-9a6c-5748-9c1c-f9c7231a4531"
version = "1.16.1+1"

[[Libmount_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "9c30530bf0effd46e15e0fdcf2b8636e78cbbd73"
uuid = "4b2f31a3-9ecc-558c-b454-b3730dcb73e9"
version = "2.35.0+0"

[[Libtiff_jll]]
deps = ["Artifacts", "JLLWrappers", "JpegTurbo_jll", "LERC_jll", "Libdl", "Pkg", "Zlib_jll", "Zstd_jll"]
git-tree-sha1 = "3eb79b0ca5764d4799c06699573fd8f533259713"
uuid = "89763e89-9b03-5906-acba-b20f662cd828"
version = "4.4.0+0"

[[Libuuid_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "7f3efec06033682db852f8b3bc3c1d2b0a0ab066"
uuid = "38a345b3-de98-5d2b-a5d3-14cd9215e700"
version = "2.36.0+0"

[[LinearAlgebra]]
deps = ["Libdl"]
uuid = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"

[[LinearMaps]]
deps = ["LinearAlgebra", "SparseArrays", "Statistics"]
git-tree-sha1 = "d1b46faefb7c2f48fdec69e6f3cc34857769bc15"
uuid = "7a12625a-238d-50fd-b39a-03d52299707e"
version = "3.8.0"

[[LogExpFunctions]]
deps = ["ChainRulesCore", "ChangesOfVariables", "DocStringExtensions", "InverseFunctions", "IrrationalConstants", "LinearAlgebra"]
git-tree-sha1 = "94d9c52ca447e23eac0c0f074effbcd38830deb5"
uuid = "2ab3a3ac-af41-5b50-aa03-7779005ae688"
version = "0.3.18"

[[Logging]]
uuid = "56ddb016-857b-54e1-b83d-db4d58db5568"

[[LoggingExtras]]
deps = ["Dates", "Logging"]
git-tree-sha1 = "5d4d2d9904227b8bd66386c1138cf4d5ffa826bf"
uuid = "e6f89c97-d47a-5376-807f-9c37f3926c36"
version = "0.4.9"

[[MacroTools]]
deps = ["Markdown", "Random"]
git-tree-sha1 = "42324d08725e200c23d4dfb549e0d5d89dede2d2"
uuid = "1914dd2f-81c6-5fcd-8719-6d5c9610ff09"
version = "0.5.10"

[[Manifolds]]
deps = ["Colors", "Distributions", "Einsum", "Graphs", "HybridArrays", "Kronecker", "LinearAlgebra", "ManifoldsBase", "Markdown", "MatrixEquations", "Quaternions", "Random", "RecipesBase", "RecursiveArrayTools", "Requires", "SimpleWeightedGraphs", "SpecialFunctions", "StaticArrays", "Statistics", "StatsBase"]
git-tree-sha1 = "d569c649333e42aa8e2bb40a050b7fd842ec255e"
uuid = "1cead3c2-87b3-11e9-0ccd-23c62b72b94e"
version = "0.8.35"

[[ManifoldsBase]]
deps = ["LinearAlgebra", "Markdown"]
git-tree-sha1 = "9e2772a950c5b5a6ac47fd2480b8b47be66b93cd"
uuid = "3362f125-f0bb-47a3-aa74-596ffd7ef2fb"
version = "0.13.22"

[[Markdown]]
deps = ["Base64"]
uuid = "d6f4376e-aef5-505a-96c1-9c027394607a"

[[MatrixEquations]]
deps = ["LinearAlgebra", "LinearMaps"]
git-tree-sha1 = "3b284e9c98f645232f9cf07d4118093801729d43"
uuid = "99c1a7ee-ab34-5fd5-8076-27c950a045f4"
version = "2.2.2"

[[MbedTLS]]
deps = ["Dates", "MbedTLS_jll", "MozillaCACerts_jll", "Random", "Sockets"]
git-tree-sha1 = "03a9b9718f5682ecb107ac9f7308991db4ce395b"
uuid = "739be429-bea8-5141-9913-cc70e7f3736d"
version = "1.1.7"

[[MbedTLS_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "c8ffd9c3-330d-5841-b78e-0817d7145fa1"

[[Measures]]
git-tree-sha1 = "e498ddeee6f9fdb4551ce855a46f54dbd900245f"
uuid = "442fdcdd-2543-5da2-b0f3-8c86c306513e"
version = "0.3.1"

[[Missings]]
deps = ["DataAPI"]
git-tree-sha1 = "bf210ce90b6c9eed32d25dbcae1ebc565df2687f"
uuid = "e1d29d7a-bbdc-5cf2-9ac0-f12de2c33e28"
version = "1.0.2"

[[Mmap]]
uuid = "a63ad114-7e13-5084-954f-fe012c677804"

[[MozillaCACerts_jll]]
uuid = "14a3606d-f60d-562e-9121-12d972cd8159"

[[NaNMath]]
deps = ["OpenLibm_jll"]
git-tree-sha1 = "a7c3d1da1189a1c2fe843a3bfa04d18d20eb3211"
uuid = "77ba4419-2d1f-58cd-9bb1-8ffee604a2e3"
version = "1.0.1"

[[NamedDims]]
deps = ["AbstractFFTs", "ChainRulesCore", "CovarianceEstimation", "LinearAlgebra", "Pkg", "Requires", "Statistics"]
git-tree-sha1 = "cb8ebcee2b4e07b72befb9def593baef8aa12f07"
uuid = "356022a1-0364-5f58-8944-0da4b18d706f"
version = "0.2.50"

[[NetworkOptions]]
uuid = "ca575930-c2e3-43a9-ace4-1e988b2c1908"

[[Ogg_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "887579a3eb005446d514ab7aeac5d1d027658b8f"
uuid = "e7412a2a-1a6e-54c0-be00-318e2571c051"
version = "1.3.5+1"

[[OpenLibm_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "05823500-19ac-5b8b-9628-191a04bc5112"

[[OpenSSL]]
deps = ["BitFlags", "Dates", "MozillaCACerts_jll", "OpenSSL_jll", "Sockets"]
git-tree-sha1 = "3c3c4a401d267b04942545b1e964a20279587fd7"
uuid = "4d8831e6-92b7-49fb-bdf8-b643e874388c"
version = "1.3.0"

[[OpenSSL_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "e60321e3f2616584ff98f0a4f18d98ae6f89bbb3"
uuid = "458c3c95-2e84-50aa-8efc-19380b2a3a95"
version = "1.1.17+0"

[[OpenSpecFun_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "13652491f6856acfd2db29360e1bbcd4565d04f1"
uuid = "efe28fd5-8261-553b-a9e1-b2916fc3738e"
version = "0.5.5+0"

[[Opus_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "51a08fb14ec28da2ec7a927c4337e4332c2a4720"
uuid = "91d4177d-7536-5919-b921-800302f37372"
version = "1.3.2+0"

[[OrderedCollections]]
git-tree-sha1 = "85f8e6578bf1f9ee0d11e7bb1b1456435479d47c"
uuid = "bac558e1-5e72-5ebc-8fee-abe8a469f55d"
version = "1.4.1"

[[PCRE2_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "efcefdf7-47ab-520b-bdef-62a2eaa19f15"

[[PDMats]]
deps = ["LinearAlgebra", "SparseArrays", "SuiteSparse"]
git-tree-sha1 = "cf494dca75a69712a72b80bc48f59dcf3dea63ec"
uuid = "90014a1f-27ba-587c-ab20-58faa44d9150"
version = "0.11.16"

[[Parsers]]
deps = ["Dates"]
git-tree-sha1 = "6c01a9b494f6d2a9fc180a08b182fcb06f0958a0"
uuid = "69de0a69-1ddd-5017-9359-2bf0b02dc9f0"
version = "2.4.2"

[[Pipe]]
git-tree-sha1 = "6842804e7867b115ca9de748a0cf6b364523c16d"
uuid = "b98c9c47-44ae-5843-9183-064241ee97a0"
version = "1.3.0"

[[Pixman_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "b4f5d02549a10e20780a24fce72bea96b6329e29"
uuid = "30392449-352a-5448-841d-b1acce4e97dc"
version = "0.40.1+0"

[[Pkg]]
deps = ["Artifacts", "Dates", "Downloads", "LibGit2", "Libdl", "Logging", "Markdown", "Printf", "REPL", "Random", "SHA", "Serialization", "TOML", "Tar", "UUIDs", "p7zip_jll"]
uuid = "44cfe95a-1eb2-52ea-b672-e2afdf69b78f"

[[PlotThemes]]
deps = ["PlotUtils", "Statistics"]
git-tree-sha1 = "1f03a2d339f42dca4a4da149c7e15e9b896ad899"
uuid = "ccf2f8ad-2431-5c83-bf29-c5338b663b6a"
version = "3.1.0"

[[PlotUtils]]
deps = ["ColorSchemes", "Colors", "Dates", "Printf", "Random", "Reexport", "SnoopPrecompile", "Statistics"]
git-tree-sha1 = "21303256d239f6b484977314674aef4bb1fe4420"
uuid = "995b91a9-d308-5afd-9ec6-746e21dbc043"
version = "1.3.1"

[[Plots]]
deps = ["Base64", "Contour", "Dates", "Downloads", "FFMPEG", "FixedPointNumbers", "GR", "JLFzf", "JSON", "LaTeXStrings", "Latexify", "LinearAlgebra", "Measures", "NaNMath", "Pkg", "PlotThemes", "PlotUtils", "Printf", "REPL", "Random", "RecipesBase", "RecipesPipeline", "Reexport", "RelocatableFolders", "Requires", "Scratch", "Showoff", "SnoopPrecompile", "SparseArrays", "Statistics", "StatsBase", "UUIDs", "UnicodeFun", "Unzip"]
git-tree-sha1 = "0a56829d264eb1bc910cf7c39ac008b5bcb5a0d9"
uuid = "91a5bcdd-55d7-5caf-9e0b-520d859cae80"
version = "1.35.5"

[[Preferences]]
deps = ["TOML"]
git-tree-sha1 = "47e5f437cc0e7ef2ce8406ce1e7e24d44915f88d"
uuid = "21216c6a-2e73-6563-6e65-726566657250"
version = "1.3.0"

[[Printf]]
deps = ["Unicode"]
uuid = "de0858da-6303-5e67-8744-51eddeeeb8d7"

[[Qt5Base_jll]]
deps = ["Artifacts", "CompilerSupportLibraries_jll", "Fontconfig_jll", "Glib_jll", "JLLWrappers", "Libdl", "Libglvnd_jll", "OpenSSL_jll", "Pkg", "Xorg_libXext_jll", "Xorg_libxcb_jll", "Xorg_xcb_util_image_jll", "Xorg_xcb_util_keysyms_jll", "Xorg_xcb_util_renderutil_jll", "Xorg_xcb_util_wm_jll", "Zlib_jll", "xkbcommon_jll"]
git-tree-sha1 = "c6c0f690d0cc7caddb74cef7aa847b824a16b256"
uuid = "ea2cea3b-5b76-57ae-a6ef-0a8af62496e1"
version = "5.15.3+1"

[[QuadGK]]
deps = ["DataStructures", "LinearAlgebra"]
git-tree-sha1 = "97aa253e65b784fd13e83774cadc95b38011d734"
uuid = "1fd47b50-473d-5c70-9696-f719f8f3bcdc"
version = "2.6.0"

[[Quaternions]]
deps = ["LinearAlgebra", "Random"]
git-tree-sha1 = "fd78cbfa5f5be5f81a482908f8ccfad611dca9a9"
uuid = "94ee1d12-ae83-5a48-8b1c-48b8ff168ae0"
version = "0.6.0"

[[REPL]]
deps = ["InteractiveUtils", "Markdown", "Sockets", "Unicode"]
uuid = "3fa0cd96-eef1-5676-8a61-b3b8758bbffb"

[[Random]]
deps = ["Serialization"]
uuid = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"

[[RecipesBase]]
deps = ["SnoopPrecompile"]
git-tree-sha1 = "d12e612bba40d189cead6ff857ddb67bd2e6a387"
uuid = "3cdcf5f2-1ef4-517c-9805-6587b60abb01"
version = "1.3.1"

[[RecipesPipeline]]
deps = ["Dates", "NaNMath", "PlotUtils", "RecipesBase", "SnoopPrecompile"]
git-tree-sha1 = "9b1c0c8e9188950e66fc28f40bfe0f8aac311fe0"
uuid = "01d81517-befc-4cb6-b9ec-a95719d0359c"
version = "0.6.7"

[[RecursiveArrayTools]]
deps = ["Adapt", "ArrayInterfaceCore", "ArrayInterfaceStaticArraysCore", "ChainRulesCore", "DocStringExtensions", "FillArrays", "GPUArraysCore", "IteratorInterfaceExtensions", "LinearAlgebra", "RecipesBase", "StaticArraysCore", "Statistics", "Tables", "ZygoteRules"]
git-tree-sha1 = "3004608dc42101a944e44c1c68b599fa7c669080"
uuid = "731186ca-8d62-57ce-b412-fbd966d074cd"
version = "2.32.0"

[[Reexport]]
git-tree-sha1 = "45e428421666073eab6f2da5c9d310d99bb12f9b"
uuid = "189a3867-3050-52da-a836-e630ba90ab69"
version = "1.2.2"

[[RelocatableFolders]]
deps = ["SHA", "Scratch"]
git-tree-sha1 = "90bc7a7c96410424509e4263e277e43250c05691"
uuid = "05181044-ff0b-4ac5-8273-598c1e38db00"
version = "1.0.0"

[[Requires]]
deps = ["UUIDs"]
git-tree-sha1 = "838a3a4188e2ded87a4f9f184b4b0d78a1e91cb7"
uuid = "ae029012-a4dd-5104-9daa-d747884805df"
version = "1.3.0"

[[Rmath]]
deps = ["Random", "Rmath_jll"]
git-tree-sha1 = "bf3188feca147ce108c76ad82c2792c57abe7b1f"
uuid = "79098fc4-a85e-5d69-aa6a-4863f24498fa"
version = "0.7.0"

[[Rmath_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "68db32dff12bb6127bac73c209881191bf0efbb7"
uuid = "f50d1b31-88e8-58de-be2c-1cc44531875f"
version = "0.3.0+0"

[[SHA]]
uuid = "ea8e919c-243c-51af-8825-aaa63cd721ce"

[[Scratch]]
deps = ["Dates"]
git-tree-sha1 = "f94f779c94e58bf9ea243e77a37e16d9de9126bd"
uuid = "6c6a2e73-6563-6170-7368-637461726353"
version = "1.1.1"

[[Serialization]]
uuid = "9e88b42a-f829-5b0c-bbe9-9e923198166b"

[[SharedArrays]]
deps = ["Distributed", "Mmap", "Random", "Serialization"]
uuid = "1a1011a3-84de-559e-8e89-a11a2f7dc383"

[[Showoff]]
deps = ["Dates", "Grisu"]
git-tree-sha1 = "91eddf657aca81df9ae6ceb20b959ae5653ad1de"
uuid = "992d4aef-0814-514b-bc4d-f2e9a6c4116f"
version = "1.0.3"

[[SimpleBufferStream]]
git-tree-sha1 = "874e8867b33a00e784c8a7e4b60afe9e037b74e1"
uuid = "777ac1f9-54b0-4bf8-805c-2214025038e7"
version = "1.1.0"

[[SimpleTraits]]
deps = ["InteractiveUtils", "MacroTools"]
git-tree-sha1 = "5d7e3f4e11935503d3ecaf7186eac40602e7d231"
uuid = "699a6c99-e7fa-54fc-8d76-47d257e15c1d"
version = "0.9.4"

[[SimpleWeightedGraphs]]
deps = ["Graphs", "LinearAlgebra", "Markdown", "SparseArrays", "Test"]
git-tree-sha1 = "a6f404cc44d3d3b28c793ec0eb59af709d827e4e"
uuid = "47aef6b3-ad0c-573a-a1e2-d07658019622"
version = "1.2.1"

[[SnoopPrecompile]]
git-tree-sha1 = "f604441450a3c0569830946e5b33b78c928e1a85"
uuid = "66db9d55-30c0-4569-8b51-7e840670fc0c"
version = "1.0.1"

[[Sockets]]
uuid = "6462fe0b-24de-5631-8697-dd941f90decc"

[[SortingAlgorithms]]
deps = ["DataStructures"]
git-tree-sha1 = "b3363d7460f7d098ca0912c69b082f75625d7508"
uuid = "a2af1166-a08f-5f64-846c-94a0d3cef48c"
version = "1.0.1"

[[SparseArrays]]
deps = ["LinearAlgebra", "Random"]
uuid = "2f01184e-e22b-5df5-ae63-d93ebab69eaf"

[[SpecialFunctions]]
deps = ["ChainRulesCore", "IrrationalConstants", "LogExpFunctions", "OpenLibm_jll", "OpenSpecFun_jll"]
git-tree-sha1 = "d75bda01f8c31ebb72df80a46c88b25d1c79c56d"
uuid = "276daf66-3868-5448-9aa4-cd146d93841b"
version = "2.1.7"

[[StaticArrays]]
deps = ["LinearAlgebra", "Random", "StaticArraysCore", "Statistics"]
git-tree-sha1 = "f86b3a049e5d05227b10e15dbb315c5b90f14988"
uuid = "90137ffa-7385-5640-81b9-e52037218182"
version = "1.5.9"

[[StaticArraysCore]]
git-tree-sha1 = "6b7ba252635a5eff6a0b0664a41ee140a1c9e72a"
uuid = "1e83bf80-4336-4d27-bf5d-d5a4f845583c"
version = "1.4.0"

[[Statistics]]
deps = ["LinearAlgebra", "SparseArrays"]
uuid = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"

[[StatsAPI]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "f9af7f195fb13589dd2e2d57fdb401717d2eb1f6"
uuid = "82ae8749-77ed-4fe6-ae5f-f523153014b0"
version = "1.5.0"

[[StatsBase]]
deps = ["DataAPI", "DataStructures", "LinearAlgebra", "LogExpFunctions", "Missings", "Printf", "Random", "SortingAlgorithms", "SparseArrays", "Statistics", "StatsAPI"]
git-tree-sha1 = "d1bf48bfcc554a3761a133fe3a9bb01488e06916"
uuid = "2913bbd2-ae8a-5f71-8c99-4fb6c76f3a91"
version = "0.33.21"

[[StatsFuns]]
deps = ["ChainRulesCore", "HypergeometricFunctions", "InverseFunctions", "IrrationalConstants", "LogExpFunctions", "Reexport", "Rmath", "SpecialFunctions"]
git-tree-sha1 = "5783b877201a82fc0014cbf381e7e6eb130473a4"
uuid = "4c63d2b9-4356-54db-8cca-17b64c39e42c"
version = "1.0.1"

[[SuiteSparse]]
deps = ["Libdl", "LinearAlgebra", "Serialization", "SparseArrays"]
uuid = "4607b0f0-06f3-5cda-b6b1-a6196a1729e9"

[[TOML]]
deps = ["Dates"]
uuid = "fa267f1f-6049-4f14-aa54-33bafae1ed76"

[[TableTraits]]
deps = ["IteratorInterfaceExtensions"]
git-tree-sha1 = "c06b2f539df1c6efa794486abfb6ed2022561a39"
uuid = "3783bdb8-4a98-5b6b-af9a-565f29a5fe9c"
version = "1.0.1"

[[Tables]]
deps = ["DataAPI", "DataValueInterfaces", "IteratorInterfaceExtensions", "LinearAlgebra", "OrderedCollections", "TableTraits", "Test"]
git-tree-sha1 = "c79322d36826aa2f4fd8ecfa96ddb47b174ac78d"
uuid = "bd369af6-aec1-5ad0-b16a-f7cc5008161c"
version = "1.10.0"

[[Tar]]
deps = ["ArgTools", "SHA"]
uuid = "a4e569a6-e804-4fa4-b0f3-eef7a1d5b13e"

[[TensorCore]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "1feb45f88d133a655e001435632f019a9a1bcdb6"
uuid = "62fd8b95-f654-4bbd-a8a5-9c27f68ccd50"
version = "0.1.1"

[[Test]]
deps = ["InteractiveUtils", "Logging", "Random", "Serialization"]
uuid = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

[[TranscodingStreams]]
deps = ["Random", "Test"]
git-tree-sha1 = "8a75929dcd3c38611db2f8d08546decb514fcadf"
uuid = "3bb67fe8-82b1-5028-8e26-92a6c54297fa"
version = "0.9.9"

[[URIs]]
git-tree-sha1 = "e59ecc5a41b000fa94423a578d29290c7266fc10"
uuid = "5c2747f8-b7ea-4ff2-ba2e-563bfd36b1d4"
version = "1.4.0"

[[UUIDs]]
deps = ["Random", "SHA"]
uuid = "cf7118a7-6976-5b1a-9a39-7adc72f591a4"

[[Unicode]]
uuid = "4ec0a83e-493e-50e2-b9ac-8f72acf5a8f5"

[[UnicodeFun]]
deps = ["REPL"]
git-tree-sha1 = "53915e50200959667e78a92a418594b428dffddf"
uuid = "1cfade01-22cf-5700-b092-accc4b62d6e1"
version = "0.4.1"

[[Unzip]]
git-tree-sha1 = "34db80951901073501137bdbc3d5a8e7bbd06670"
uuid = "41fe7b60-77ed-43a1-b4f0-825fd5a5650d"
version = "0.1.2"

[[Wayland_jll]]
deps = ["Artifacts", "Expat_jll", "JLLWrappers", "Libdl", "Libffi_jll", "Pkg", "XML2_jll"]
git-tree-sha1 = "3e61f0b86f90dacb0bc0e73a0c5a83f6a8636e23"
uuid = "a2964d1f-97da-50d4-b82a-358c7fce9d89"
version = "1.19.0+0"

[[Wayland_protocols_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "4528479aa01ee1b3b4cd0e6faef0e04cf16466da"
uuid = "2381bf8a-dfd0-557d-9999-79630e7b1b91"
version = "1.25.0+0"

[[XML2_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Libiconv_jll", "Pkg", "Zlib_jll"]
git-tree-sha1 = "58443b63fb7e465a8a7210828c91c08b92132dff"
uuid = "02c8fc9c-b97f-50b9-bbe4-9be30ff0a78a"
version = "2.9.14+0"

[[XSLT_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Libgcrypt_jll", "Libgpg_error_jll", "Libiconv_jll", "Pkg", "XML2_jll", "Zlib_jll"]
git-tree-sha1 = "91844873c4085240b95e795f692c4cec4d805f8a"
uuid = "aed1982a-8fda-507f-9586-7b0439959a61"
version = "1.1.34+0"

[[Xorg_libX11_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libxcb_jll", "Xorg_xtrans_jll"]
git-tree-sha1 = "5be649d550f3f4b95308bf0183b82e2582876527"
uuid = "4f6342f7-b3d2-589e-9d20-edeb45f2b2bc"
version = "1.6.9+4"

[[Xorg_libXau_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "4e490d5c960c314f33885790ed410ff3a94ce67e"
uuid = "0c0b7dd1-d40b-584c-a123-a41640f87eec"
version = "1.0.9+4"

[[Xorg_libXcursor_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libXfixes_jll", "Xorg_libXrender_jll"]
git-tree-sha1 = "12e0eb3bc634fa2080c1c37fccf56f7c22989afd"
uuid = "935fb764-8cf2-53bf-bb30-45bb1f8bf724"
version = "1.2.0+4"

[[Xorg_libXdmcp_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "4fe47bd2247248125c428978740e18a681372dd4"
uuid = "a3789734-cfe1-5b06-b2d0-1dd0d9d62d05"
version = "1.1.3+4"

[[Xorg_libXext_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libX11_jll"]
git-tree-sha1 = "b7c0aa8c376b31e4852b360222848637f481f8c3"
uuid = "1082639a-0dae-5f34-9b06-72781eeb8cb3"
version = "1.3.4+4"

[[Xorg_libXfixes_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libX11_jll"]
git-tree-sha1 = "0e0dc7431e7a0587559f9294aeec269471c991a4"
uuid = "d091e8ba-531a-589c-9de9-94069b037ed8"
version = "5.0.3+4"

[[Xorg_libXi_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libXext_jll", "Xorg_libXfixes_jll"]
git-tree-sha1 = "89b52bc2160aadc84d707093930ef0bffa641246"
uuid = "a51aa0fd-4e3c-5386-b890-e753decda492"
version = "1.7.10+4"

[[Xorg_libXinerama_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libXext_jll"]
git-tree-sha1 = "26be8b1c342929259317d8b9f7b53bf2bb73b123"
uuid = "d1454406-59df-5ea1-beac-c340f2130bc3"
version = "1.1.4+4"

[[Xorg_libXrandr_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libXext_jll", "Xorg_libXrender_jll"]
git-tree-sha1 = "34cea83cb726fb58f325887bf0612c6b3fb17631"
uuid = "ec84b674-ba8e-5d96-8ba1-2a689ba10484"
version = "1.5.2+4"

[[Xorg_libXrender_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libX11_jll"]
git-tree-sha1 = "19560f30fd49f4d4efbe7002a1037f8c43d43b96"
uuid = "ea2f1a96-1ddc-540d-b46f-429655e07cfa"
version = "0.9.10+4"

[[Xorg_libpthread_stubs_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "6783737e45d3c59a4a4c4091f5f88cdcf0908cbb"
uuid = "14d82f49-176c-5ed1-bb49-ad3f5cbd8c74"
version = "0.1.0+3"

[[Xorg_libxcb_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "XSLT_jll", "Xorg_libXau_jll", "Xorg_libXdmcp_jll", "Xorg_libpthread_stubs_jll"]
git-tree-sha1 = "daf17f441228e7a3833846cd048892861cff16d6"
uuid = "c7cfdc94-dc32-55de-ac96-5a1b8d977c5b"
version = "1.13.0+3"

[[Xorg_libxkbfile_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libX11_jll"]
git-tree-sha1 = "926af861744212db0eb001d9e40b5d16292080b2"
uuid = "cc61e674-0454-545c-8b26-ed2c68acab7a"
version = "1.1.0+4"

[[Xorg_xcb_util_image_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_xcb_util_jll"]
git-tree-sha1 = "0fab0a40349ba1cba2c1da699243396ff8e94b97"
uuid = "12413925-8142-5f55-bb0e-6d7ca50bb09b"
version = "0.4.0+1"

[[Xorg_xcb_util_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libxcb_jll"]
git-tree-sha1 = "e7fd7b2881fa2eaa72717420894d3938177862d1"
uuid = "2def613f-5ad1-5310-b15b-b15d46f528f5"
version = "0.4.0+1"

[[Xorg_xcb_util_keysyms_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_xcb_util_jll"]
git-tree-sha1 = "d1151e2c45a544f32441a567d1690e701ec89b00"
uuid = "975044d2-76e6-5fbe-bf08-97ce7c6574c7"
version = "0.4.0+1"

[[Xorg_xcb_util_renderutil_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_xcb_util_jll"]
git-tree-sha1 = "dfd7a8f38d4613b6a575253b3174dd991ca6183e"
uuid = "0d47668e-0667-5a69-a72c-f761630bfb7e"
version = "0.3.9+1"

[[Xorg_xcb_util_wm_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_xcb_util_jll"]
git-tree-sha1 = "e78d10aab01a4a154142c5006ed44fd9e8e31b67"
uuid = "c22f9ab0-d5fe-5066-847c-f4bb1cd4e361"
version = "0.4.1+1"

[[Xorg_xkbcomp_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_libxkbfile_jll"]
git-tree-sha1 = "4bcbf660f6c2e714f87e960a171b119d06ee163b"
uuid = "35661453-b289-5fab-8a00-3d9160c6a3a4"
version = "1.4.2+4"

[[Xorg_xkeyboard_config_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Xorg_xkbcomp_jll"]
git-tree-sha1 = "5c8424f8a67c3f2209646d4425f3d415fee5931d"
uuid = "33bec58e-1273-512f-9401-5d533626f822"
version = "2.27.0+4"

[[Xorg_xtrans_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "79c31e7844f6ecf779705fbc12146eb190b7d845"
uuid = "c5fb5394-a638-5e4d-96e5-b29de1b5cf10"
version = "1.4.0+3"

[[Zlib_jll]]
deps = ["Libdl"]
uuid = "83775a58-1f1d-513f-b197-d71354ab007a"

[[Zstd_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "e45044cd873ded54b6a5bac0eb5c971392cf1927"
uuid = "3161d3a3-bdf6-5164-811a-617609db77b4"
version = "1.5.2+0"

[[ZygoteRules]]
deps = ["MacroTools"]
git-tree-sha1 = "8c1a8e4dfacb1fd631745552c8db35d0deb09ea0"
uuid = "700de1a5-db45-46bc-99cf-38207098b444"
version = "0.2.2"

[[fzf_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "868e669ccb12ba16eaf50cb2957ee2ff61261c56"
uuid = "214eeab7-80f7-51ab-84ad-2988db7cef09"
version = "0.29.0+0"

[[libaom_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "3a2ea60308f0996d26f1e5354e10c24e9ef905d4"
uuid = "a4ae2306-e953-59d6-aa16-d00cac43593b"
version = "3.4.0+0"

[[libass_jll]]
deps = ["Artifacts", "Bzip2_jll", "FreeType2_jll", "FriBidi_jll", "HarfBuzz_jll", "JLLWrappers", "Libdl", "Pkg", "Zlib_jll"]
git-tree-sha1 = "5982a94fcba20f02f42ace44b9894ee2b140fe47"
uuid = "0ac62f75-1d6f-5e53-bd7c-93b484bb37c0"
version = "0.15.1+0"

[[libfdk_aac_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "daacc84a041563f965be61859a36e17c4e4fcd55"
uuid = "f638f0a6-7fb0-5443-88ba-1cc74229b280"
version = "2.0.2+0"

[[libpng_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Zlib_jll"]
git-tree-sha1 = "94d180a6d2b5e55e447e2d27a29ed04fe79eb30c"
uuid = "b53b4c65-9356-5827-b1ea-8c7a1a84506f"
version = "1.6.38+0"

[[libvorbis_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Ogg_jll", "Pkg"]
git-tree-sha1 = "b910cb81ef3fe6e78bf6acee440bda86fd6ae00c"
uuid = "f27f6e37-5d2b-51aa-960f-b287f2bc3b7a"
version = "1.3.7+1"

[[nghttp2_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850ede-7688-5339-a07c-302acd2aaf8d"

[[p7zip_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "3f19e933-33d8-53b3-aaab-bd5110c3b7a0"

[[x264_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "4fea590b89e6ec504593146bf8b988b2c00922b2"
uuid = "1270edf5-f2f9-52d2-97e9-ab00b5d0237a"
version = "2021.5.5+0"

[[x265_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg"]
git-tree-sha1 = "ee567a171cce03570d77ad3a43e90218e38937a9"
uuid = "dfaa095f-4041-5dcd-9319-2fabd8486b76"
version = "3.5.0+0"

[[xkbcommon_jll]]
deps = ["Artifacts", "JLLWrappers", "Libdl", "Pkg", "Wayland_jll", "Wayland_protocols_jll", "Xorg_libxcb_jll", "Xorg_xkeyboard_config_jll"]
git-tree-sha1 = "9ebfc140cc56e8c2156a15ceac2f0302e327ac0a"
uuid = "d8fb68d0-12a3-5cfd-a85a-d49703b185fd"
version = "1.4.1+0"
"""

# ╔═╡ Cell order:
# ╠═dd850c42-627d-4885-9516-857a2883fa55
# ╠═c935e5a1-dff5-435a-8631-49f893e4288a
# ╠═22ff5f42-3bb2-4a43-bd00-6ff35a27962f
# ╠═c7d79774-d721-4271-b1b5-ea47bc6aa0a8
# ╠═48c852dd-b633-4c09-aa72-6a552f589571
# ╠═d9322024-8122-468f-b319-284a9d5858b7
# ╠═c8924dad-8121-4893-848f-a8e2d3f34579
# ╠═04ab2a93-a49f-4e91-be9f-7e439d5c161f
# ╠═a8b1acbe-e6b1-4319-88da-7edc334db542
# ╠═40a3d7bc-f862-4864-b2e4-9593d4a41e9c
# ╠═591e461e-173d-479a-9b91-fc3053b857a9
# ╠═08419c9c-1ded-4671-84cb-e79c611c4177
# ╠═7c0c84cf-055a-450d-80c0-e4cebc01a78c
# ╠═1a86c737-81f5-4af9-97bc-4b0e32a4d687
# ╠═ea40b02b-cab7-4c57-aec9-fe70b26ebb54
# ╠═41613c73-6dd8-4c9c-8248-85e4cbc15774
# ╠═fd3906cd-741f-4549-a71b-4e04bb90f1f2
# ╠═ec17392d-3822-4a9b-b4b5-fadf40d45718
# ╠═5ea2bbd4-ed74-45d2-b54e-bbbb3eafc35a
# ╠═ce54fa38-eadb-42c4-86a3-17d156a2683d
# ╠═e0cd8266-c28d-4c52-b3c7-4f00eeb77505
# ╠═686d9dd9-86c5-4e18-9743-cf16095a6c19
# ╠═ae433651-0a12-435e-8f2e-3cf6f24600fb
# ╠═0aad227c-6a05-48cf-850f-2f18d3caf78a
# ╠═a3e577ee-76f9-4447-8fc9-140434d1fa9c
# ╠═f2289998-294d-429d-b495-ad7941b5e1ab
# ╠═6658c1d1-c2c2-4c90-b509-cdbef9f35417
# ╠═74c3d4ae-6b9f-47c4-a0a3-b786f3cacc83
# ╠═09d5a17b-46e8-41cf-8417-652b6dec6c98
# ╠═6d136817-0a5c-4103-a9d9-a65f3b92db89
# ╠═74b41511-cd14-4a1a-8144-84a92299b081
# ╠═8c75e3ac-316f-4ca2-9864-92adb71f8d2b
# ╠═5015763d-6e2d-42c9-a302-72ad75e2e0b5
# ╠═ef29b250-cf46-40f2-b668-9c59356c10b1
# ╠═71a63b54-a409-460a-aab0-b6e5be3c8589
# ╠═e018ff9c-f0ce-432d-a04d-c8ccfab1fbcf
# ╠═879d4039-2e70-4e17-a26c-38054e22101b
# ╠═22d42d24-2de2-4b2c-815b-0a3e2bf45d4a
# ╠═053260f6-521f-441f-bcda-f38626e3649a
# ╠═6f4b077b-f3ef-4468-83bf-8643b8f7e7e4
# ╠═7a84ab58-a0d0-4fc4-8b87-d7461205920b
# ╠═d4d3cc84-86ee-4e7d-af4f-dbea1c010775
# ╠═7c11788d-a58e-4a49-9a74-0570e89cc0de
# ╠═38f42070-4811-42f9-bebb-139521578dd5
# ╠═cb6651a0-7bce-46b8-9eb0-2c36a8018ccc
# ╠═1c04caed-db65-4619-9122-ab72971d01c5
# ╠═0fa0e434-085c-4961-a2e3-652beaf5ac06
# ╠═528914e3-0fb1-4a43-a321-c209721ccede
# ╠═b0fcc163-37e7-4ad8-950d-713ce6afa874
# ╠═4643f16b-d3e8-4ec8-8599-4f4664f33eb7
# ╠═083b3ff5-8d9d-46a5-909d-64174cf6ac2b
# ╠═09197117-175f-4d0a-8513-418e4a2bd44f
# ╠═01619322-e84d-464f-8d19-6e4bae0061b5
# ╠═ad1791b1-a4dc-49d6-8add-1432071360b3
# ╠═20ea08df-e39d-415e-a00d-d7e2a0a1b251
# ╠═e64b4f76-5b87-4897-a794-8360226abdda
# ╠═e6bb27b6-1b5f-4d59-bf84-58389d8b9b3e
# ╠═e548e4cd-8d16-46c6-b442-af9631d4b99e
# ╠═ff01e3e9-238f-4e33-a136-1dc43e722759
# ╠═682e10aa-4109-4b24-b4d6-81adb7129c60
# ╠═e16184e2-80dc-4175-93a3-8af7ae2adb41
# ╠═4fdda677-11fa-4d01-b90a-c64e48c0bcb4
# ╠═aed60318-2fb2-4c5c-9504-e575f3509847
# ╠═5952b7c7-6d87-458b-b7c0-e26b2d7fbbd6
# ╠═f26acd44-5f5c-4688-939c-a4db8c91595b
# ╠═4f88bb3b-de79-4bd4-ab8e-9e5f68cf8cb7
# ╠═ccb44d88-1f4c-441a-830c-c8b1e7f9150b
# ╠═dbd7edf6-2aa6-4386-ad0a-7917dcbbd519
# ╠═4ef64355-19cb-4b5b-9c13-f066dc4351f0
# ╠═92211e50-b15e-429d-a330-6303219aeda8
# ╠═b624efc3-f384-41a9-9df6-022e8fe58b05
# ╠═9ed4ad8c-5506-4163-82e4-4216d615ad85
# ╠═c9e2aede-26c4-4d6f-acbc-102ca855eab7
# ╠═8a4f31e7-5e35-4cf4-9926-49db20ed67ab
# ╠═aa3e96fb-a453-4a51-b0a1-5c0ffb7e0f28
# ╠═d5f01148-d81e-4d98-a24c-9224d9a7a5d5
# ╠═951346fa-703c-4652-b85f-7161fa61f2bd
# ╠═0ed0c873-4567-4d2e-a748-bce3d2dbf08a
# ╠═a9ff4ac2-4021-4a5d-a639-0eaa53758a23
# ╠═8b7acec9-8042-4417-a27b-9f8b058a0b34
# ╠═45c4e39c-db77-413c-a77e-6dcdc484ce63
# ╠═be4b3c8f-a8a7-4d94-9a20-ac577b60a635
# ╠═ba9ed636-a6c0-4a4c-b961-8e2a4d9463b5
# ╠═cc250424-e032-4740-9ed5-7267d143aaf3
# ╠═bad443b3-f94e-46d3-bae7-72da23bb7a11
# ╠═12f70b6d-0dd5-4516-b58d-f2d77606fc20
# ╠═5e39f082-3ac9-453d-add0-03ff68cc7615
# ╠═08ea2dbc-119b-457a-a7a3-8c7c76e65885
# ╠═e161fe96-b2b9-4068-8f2a-fc1925196955
# ╠═9d24db4e-c84f-4fa2-b027-b64f77e874b0
# ╠═0ba93020-04f2-4d20-8882-34f7392e291e
# ╠═7e309e52-87f0-4dab-9e38-af5a166e65e7
# ╠═47feff1f-f796-496b-a0ee-a7482faf139c
# ╠═39449216-e0b5-4f69-9548-5c99e65edd17
# ╠═8dd4e313-e0a4-408d-abc9-0831a67e0845
# ╠═88679086-b52c-4a5c-88fe-6db62c8254b6
# ╠═26b2be57-72b1-474c-9b77-46338c438665
# ╠═1541b449-c5ff-4771-9bdf-5c05f82c3bf5
# ╠═84621943-c11c-415c-b049-62415e9995d4
# ╠═3f68ea76-407d-4104-a9de-353fe3deed79
# ╟─00000000-0000-0000-0000-000000000001
# ╟─00000000-0000-0000-0000-000000000002
