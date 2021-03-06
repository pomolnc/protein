function a = tril(a,k)
%TRIL         Implements  tril(a,k)  for slopes
%
%   u = tril(a,k)
%
% functionality as Matlab function tril for matrices
%

% written  09/28/01     S.M. Rump
% modified 04/04/04     S.M. Rump  set round to nearest for safety
% modified 04/06/05     S.M. Rump  rounding unchanged
%

  if nargin==1
    k = 0;
  end

  index = reshape( 1:prod(a.size) , a.size );
  index = tril(index,k);
  index = index(:);

  a.r(index==0,:) = 0;
  a.s(index==0,:) = 0;
